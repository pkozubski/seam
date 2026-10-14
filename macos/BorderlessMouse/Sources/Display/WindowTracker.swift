import CoreGraphics
import Foundation

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
/// Lista jest odświeżana 30 razy na sekundę i zgłaszana tylko po zmianie.
final class WindowTracker {
    private let queue = DispatchQueue(label: "blm.display.windows", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var last: [TrackedWindow]?
    private var ownership: [Int32: (ids: Set<UInt32>, checked: TimeInterval, appIDs: Set<UInt32>?)] = [:]
    private var recentOwners: [UInt32: (window: TrackedWindow, seen: TimeInterval)] = [:]

    /// Wywoływane na kolejce trackera, tylko gdy lista się zmieniła.
    func start(displayID: CGDirectDisplayID, onChange: @escaping ([TrackedWindow]) -> Void) {
        stop()
        queue.sync { last = nil; ownership.removeAll(); recentOwners.removeAll() }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(33), leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let current = Self.snapshot(displayID: displayID)
            let windows = self.classify(self.retainingFullscreenOwners(current, displayID: displayID))
            let now = ProcessInfo.processInfo.systemUptime
            let visibleIDs = Set(current.map(\.id))
            for window in windows where !window.isPopup && !window.isMenuBar && visibleIDs.contains(window.id) {
                self.recentOwners[window.id] = (window, now)
            }
            let retainedIDs = Set(windows.map(\.id))
            self.recentOwners = self.recentOwners.filter { retainedIDs.contains($0.key) }
            guard windows != self.last else { return }
            self.last = windows
            onChange(windows)
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Wymusza ponowne wysłanie listy przy następnym odświeżeniu.
    func resend() {
        queue.async { self.last = nil }
    }

    private func classify(_ windows: [TrackedWindow]) -> [TrackedWindow] {
        let groups = Dictionary(grouping: windows.filter { !$0.isMenuBar }, by: \.pid)
        let now = ProcessInfo.processInfo.systemUptime
        ownership = ownership.filter { groups[$0.key] != nil }
        for (pid, group) in groups {
            let ids = Set(group.map(\.id))
            if ownership[pid]?.ids != ids || now - (ownership[pid]?.checked ?? 0) > 1 {
                ownership[pid] = (ids, now, WindowControl.applicationWindowIDs(pid: pid))
            }
        }
        return windows.map { window in
            guard !window.isMenuBar, !window.isPopup, let appIDs = ownership[window.pid]?.appIDs,
                  !appIDs.contains(window.id),
                  windows.contains(where: { $0.pid == window.pid && appIDs.contains($0.id)
                      && $0.frame.intersects(window.frame) }) else { return window }
            return TrackedWindow(id: window.id, pid: window.pid, frame: window.frame,
                                 isMenuBar: false, isPopup: true, title: window.title)
        }
    }

    /// Fullscreen Spaces can briefly remove the source window from the on-screen list.
    /// Keep its host while a fullscreen child is shown, but only if that source still exists
    /// on the virtual display. Returning it to a physical display removes the host immediately.
    private func retainingFullscreenOwners(_ current: [TrackedWindow], displayID: CGDirectDisplayID) -> [TrackedWindow] {
        let missing = recentOwners.values.filter { owner in !current.contains { $0.id == owner.window.id } }
        guard !missing.isEmpty,
              let all = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return current }
        let display = CGDisplayBounds(displayID)
        let now = ProcessInfo.processInfo.systemUptime
        var result = current
        for owner in missing {
            guard let info = all.first(where: { ($0[kCGWindowNumber as String] as? UInt32) == owner.window.id
                && ($0[kCGWindowOwnerPID as String] as? Int32) == owner.window.pid }),
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary),
                  display.contains(CGPoint(x: bounds.midX, y: bounds.midY)) else { continue }
            let fullscreenChild = current.contains { window in
                window.pid == owner.window.pid && window.frame.intersection(display).width >= display.width * 0.9
                    && window.frame.intersection(display).height >= display.height * 0.9
            }
            if now - owner.seen < 0.75 || fullscreenChild { result.append(owner.window) }
        }
        return result
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
