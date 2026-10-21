import CoreGraphics
import Foundation
import os

/// Okno Maca leżące na ekranie wirtualnym (tryb okien).
struct TrackedWindow: Equatable {
    let id: UInt32
    let pid: Int32
    /// Pełna ramka w globalnych punktach macOS (lewy górny róg), bez obcinania do ekranu.
    let frame: CGRect
    let isMenuBar: Bool
    let isPopup: Bool
    let title: String
}

/// Śledzi okna na ekranie wirtualnym. Każde z nich dostaje na Windowsie własne,
/// prawdziwe okno (pasek zadań, Alt+Tab, minimalizacja) i osobny strumień obrazu.
/// Lista jest zgłaszana tylko po zmianie. Odpytywanie WindowServera jest kosztowne (także
/// dla samego WindowServera), więc tempo zależy od aktywności: 30 razy na sekundę, gdy okna
/// się zmieniają albo Windows steruje oknami Maca, potem coraz rzadziej.
final class WindowTracker {
    private let queue = DispatchQueue(label: "blm.display.windows", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var last: [TrackedWindow]?
    private var ownership: [Int32: (ids: Set<UInt32>, checked: TimeInterval, appIDs: Set<UInt32>?)] = [:]
    private var state = WindowTrackingState()

    private enum Pace: Int {
        case fast = 33, medium = 100, slow = 250
        var interval: DispatchTimeInterval { .milliseconds(rawValue) }
        var leeway: DispatchTimeInterval { .milliseconds(rawValue / 6) }
    }
    /// Kolejka trackera (`timer` należy do wołającego start/stop).
    private var activeTimer: DispatchSourceTimer?
    private var pace = Pace.fast
    private var lastChange: TimeInterval = 0
    /// Ostatnie wejście z Windowsa i czy tracker jest w szybkim tempie (dowolny wątek).
    private let pacing = OSAllocatedUnfairLock(initialState: (lastInput: TimeInterval(0), fast: true))

    /// Wywoływane na kolejce trackera, tylko gdy lista się zmieniła.
    func start(displayID: CGDirectDisplayID, onChange: @escaping ([TrackedWindow]) -> Void) {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        queue.sync {
            last = nil
            ownership.removeAll()
            state = WindowTrackingState()
            pace = .fast
            lastChange = ProcessInfo.processInfo.systemUptime
            pacing.withLock { $0.fast = true }
            activeTimer = timer
        }
        timer.schedule(deadline: .now(), repeating: Pace.fast.interval, leeway: Pace.fast.leeway)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let current = Self.snapshot(displayID: displayID)
            let now = ProcessInfo.processInfo.systemUptime
            self.refreshOwnership(current, now: now)
            let existing = self.state.hasMissingOwners(in: current) ? Self.existingWindows() : []
            let windows = self.state.update(current, applicationWindows: self.ownership.compactMapValues(\.appIDs),
                                            existing: existing, display: CGDisplayBounds(displayID), now: now)
            if windows != self.last {
                self.last = windows
                self.lastChange = now
                onChange(windows)
            }
            let quiet = now - max(self.lastChange, self.pacing.withLock { $0.lastInput })
            self.setPace(quiet < 1 ? .fast : (quiet < 5 ? .medium : .slow))
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
        queue.async { self.activeTimer = nil }
    }

    /// Wymusza ponowne wysłanie listy przy następnym odświeżeniu.
    func resend() {
        queue.async {
            self.last = nil
            self.setPace(.fast, immediately: true)
        }
    }

    /// Wejście z Windowsa w trybie okien (klik, klawisz, ruch): za chwilę może się pojawić
    /// menu albo okno może się przesunąć, więc tracker wraca do pełnego tempa. Dowolny wątek, tani.
    func poke() {
        let now = ProcessInfo.processInfo.systemUptime
        let wake = pacing.withLock { state -> Bool in
            state.lastInput = now
            guard !state.fast else { return false }
            state.fast = true
            return true
        }
        if wake { queue.async { self.setPace(.fast, immediately: true) } }
    }

    /// Kolejka trackera.
    private func setPace(_ next: Pace, immediately: Bool = false) {
        guard next != pace || immediately, let timer = activeTimer else { return }
        pace = next
        pacing.withLock { $0.fast = next == .fast }
        timer.schedule(deadline: immediately ? .now() : .now() + next.interval, repeating: next.interval, leeway: next.leeway)
    }

    private func refreshOwnership(_ windows: [TrackedWindow], now: TimeInterval) {
        let groups = Dictionary(grouping: windows.filter { !$0.isMenuBar }, by: \.pid)
        ownership = ownership.filter { groups[$0.key] != nil }
        for (pid, group) in groups {
            let ids = Set(group.map(\.id))
            if ownership[pid]?.ids != ids || now - (ownership[pid]?.checked ?? 0) > 1 {
                let appIDs = WindowControl.applicationWindowIDs(pid: pid) ?? ownership[pid]?.appIDs
                ownership[pid] = (ids, now, appIDs)
            }
        }
    }

    private static func existingWindows() -> [TrackedWindow] {
        let all = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return all.compactMap { info in
            guard let id = info[kCGWindowNumber as String] as? UInt32,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary) else { return nil }
            return TrackedWindow(id: id, pid: pid, frame: bounds, isMenuBar: false, isPopup: false, title: "")
        }
    }

    /// Okna od najwyższego.
    static func snapshot(displayID: CGDirectDisplayID) -> [TrackedWindow] {
        let display = CGDisplayBounds(displayID)
        guard display.width > 0, display.height > 0,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        var windows: [TrackedWindow] = []
        for window in info {
            guard let layer = window[kCGWindowLayer as String] as? Int, (0..<1000).contains(layer),
                  let number = window[kCGWindowNumber as String] as? Int,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            let alpha = window[kCGWindowAlpha as String] as? Double ?? 1
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            let name = window[kCGWindowName as String] as? String ?? ""
            let pid = window[kCGWindowOwnerPID as String] as? Int32 ?? 0
            let isMenuBar = owner == "Window Server" && name == "Menubar"
            // Dock i elementy systemowe nie są oknami, które warto przenosić na Windows.
            if owner == "Dock" || (owner == "Window Server" && !isMenuBar) || alpha < 0.01 { continue }
            // Własne okna (m.in. okna Windows pokazywane na Macu) nie mogą wracać na Windows.
            if pid == getpid() { continue }
            let visible = bounds.intersection(display)
            guard !visible.isNull, visible.width > 2, visible.height > 2 else { continue }
            // Przezroczyste nakładki systemu i narzędzi (poza zwykłą warstwą 0) zajmują cały ekran.
            // Application-owned fullscreen surfaces must survive this filter too (video players).
            if layer != 0, !isMenuBar, pid == 0,
               visible.width * visible.height >= display.width * display.height * 0.9 { continue }
            // Okno musi leżeć głównie na ekranie wirtualnym – przeciągane z MacBooka dostaje
            // własne okno Windows dopiero, gdy jego środek przejdzie na ekran wirtualny.
            if !isMenuBar, !display.contains(CGPoint(x: bounds.midX, y: bounds.midY)) { continue }
            // Malutkie okna pomocnicze aplikacji (np. VS Code) nie są czymś, czym da się pracować.
            if layer == 0, bounds.width < 60 || bounds.height < 40 { continue }
            windows.append(TrackedWindow(id: isMenuBar ? WindowDescriptor.menuBarStreamID : UInt32(number),
                                         pid: pid, frame: isMenuBar ? visible : bounds,
                                         isMenuBar: isMenuBar, isPopup: layer != 0 && !isMenuBar,
                                         title: name.isEmpty ? owner : name))
        }
        return windows
    }

    /// Skala punkty → piksele ekranu wirtualnego (2 w trybie HiDPI).
    static func pixelScale(of displayID: CGDirectDisplayID) -> CGFloat {
        let bounds = CGDisplayBounds(displayID)
        guard bounds.width > 0, let mode = CGDisplayCopyDisplayMode(displayID) else { return 1 }
        return CGFloat(mode.pixelWidth) / bounds.width
    }

    /// Rozmiar okna w pikselach – tyle ma obraz jego strumienia.
    static func pixelSize(of window: TrackedWindow, scale: CGFloat) -> (width: Int, height: Int) {
        (max(1, Int((window.frame.width * scale).rounded())), max(1, Int((window.frame.height * scale).rounded())))
    }

    /// Opis do protokołu w pikselach ekranu wirtualnego.
    static func descriptor(_ window: TrackedWindow, on displayID: CGDirectDisplayID) -> WindowDescriptor {
        let display = CGDisplayBounds(displayID)
        let scale = pixelScale(of: displayID)
        let size = pixelSize(of: window, scale: scale)
        var flags: UInt8 = 0
        if window.isMenuBar { flags |= WindowDescriptor.menuBar }
        if window.isPopup { flags |= WindowDescriptor.popup }
        return WindowDescriptor(id: window.id, pid: window.pid,
                                x: Int32(((window.frame.minX - display.minX) * scale).rounded()),
                                y: Int32(((window.frame.minY - display.minY) * scale).rounded()),
                                width: UInt16(clamping: size.width), height: UInt16(clamping: size.height),
                                flags: flags, title: window.title)
    }

    static func normalize(_ value: CGFloat, _ total: CGFloat) -> UInt16 {
        UInt16(clamping: Int((value / total * 65535).rounded()))
    }

    /// Punkt 0…65535 → współrzędne globalne macOS na ekranie wirtualnym.
    static func point(x: UInt16, y: UInt16, on displayID: CGDirectDisplayID) -> CGPoint {
        let display = CGDisplayBounds(displayID)
        return CGPoint(x: display.minX + CGFloat(x) / 65535 * (display.width - 1),
                       y: display.minY + CGFloat(y) / 65535 * (display.height - 1))
    }
}

/// Pure lifecycle logic shared by the live tracker and regression checks. Classify before
/// retaining owners: a hidden Chrome bubble still exists in optionAll and must never be
/// kept alive just because a different Chrome window happens to fill the display.
struct WindowTrackingState {
    private var recentOwners: [UInt32: (window: TrackedWindow, seen: TimeInterval)] = [:]

    func hasMissingOwners(in current: [TrackedWindow]) -> Bool {
        let visible = Set(current.map(\.id))
        return recentOwners.keys.contains { !visible.contains($0) }
    }

    mutating func update(_ current: [TrackedWindow], applicationWindows: [Int32: Set<UInt32>],
                         existing: [TrackedWindow], display: CGRect, now: TimeInterval) -> [TrackedWindow] {
        let candidates = current + recentOwners.values.map(\.window)
        let classified = current.map { window in
            guard !window.isMenuBar, !window.isPopup, let appIDs = applicationWindows[window.pid],
                  !appIDs.contains(window.id),
                  candidates.contains(where: { owner in
                      owner.id != window.id && owner.pid == window.pid && !owner.isPopup && !owner.isMenuBar
                          && (appIDs.contains(owner.id) || recentOwners[owner.id] != nil)
                          && owner.frame.intersects(window.frame)
                  }) else { return window }
            return TrackedWindow(id: window.id, pid: window.pid, frame: window.frame,
                                 isMenuBar: false, isPopup: true, title: window.title)
        }
        let visible = Set(classified.map(\.id))
        var result = classified
        for owner in recentOwners.values where !visible.contains(owner.window.id) {
            guard let source = existing.first(where: { $0.id == owner.window.id && $0.pid == owner.window.pid }),
                  display.contains(CGPoint(x: source.frame.midX, y: source.frame.midY)) else { continue }
            let fullscreenChild = classified.contains { window in
                window.isPopup && window.pid == owner.window.pid
                    && window.frame.intersection(display).width >= display.width * 0.9
                    && window.frame.intersection(display).height >= display.height * 0.9
            }
            if now - owner.seen < 0.75 || fullscreenChild { result.append(owner.window) }
        }
        // Only positively identified application windows can survive a fullscreen transition.
        // Unknown AX data must not promote a transient to an indefinitely retained owner.
        let retained = Set(result.filter { !$0.isPopup && !$0.isMenuBar }.map(\.id))
        recentOwners = recentOwners.filter { retained.contains($0.key) }
        for window in classified where !window.isPopup && !window.isMenuBar
            && applicationWindows[window.pid]?.contains(window.id) == true {
            recentOwners[window.id] = (window, now)
        }
        return result
    }
}
