import AppKit
import CoreVideo
import QuartzCore

/// Okna Windows na Macu (kierunek Windows → Mac). Windows ma wirtualny monitor (sterownik
/// Virtual Display Driver) o rozmiarze ekranu Maca, położony przy krawędzi, za którą stoi Mac.
/// Okna przeciągnięte na ten monitor pojawiają się na Macu w tym samym miejscu jako zwykłe
/// okna macOS. Każde okno ma własny strumień H.264 (kind 2, streamID = id okna), a położenie
/// przychodzi wyłącznie z listy WINVIEW_WINDOWS i jest stosowane od razu. Mysz i klawiatura
/// nad takim oknem działają w Windowsie – Mac tylko pokazuje kursor w odpowiednim miejscu.
final class WinViewSession {
    /// Ekran Maca (globalne współrzędne CG, punkty), który odpowiada monitorowi Windows.
    let screen: CGRect
    /// Poproszenie Windowsa o klatkę kluczową (błąd dekodera). Dowolny wątek.
    var onKeyframeNeeded: (() -> Void)?
    var onClosed: ((String?) -> Void)?
    /// Kursor Windows jest w miejscu, gdzie okna Windows na Macu nie widać – Windows ma go oddać.
    var onPointerRelease: ((UInt16, UInt16) -> Void)?
    /// Użytkownik wybrał aplikację Windows w Docku / Cmd+Tab (wątek główny).
    var onActivateWindow: ((UInt32) -> Void)?
    /// „Zakończ” aplikacji Windows w Docku (wątek główny).
    var onCloseWindows: (([UInt32]) -> Void)?

    private let receiver: WinViewReceiver
    private let decodeQueue = DispatchQueue(label: "blm.winview.decode", qos: .userInteractive)
    /// Kolejka dekodera: dekoder dla każdego strumienia okna.
    private var decoders: [UInt32: H264Decompressor] = [:]
    private var listedIDs: Set<UInt32> = []
    private var lastKeyframeRequest = Date.distantPast
    private let proxies = WinWindowProxies()
    /// Aplikacje Windows jako osobne aplikacje Maca (pomocnicy); okna bez pomocnika pokazuje `proxies`.
    private let hosts = WinAppHosts()
    /// Wątek główny: ostatnia lista (do ponownego podziału po zmianie pomocników).
    private var lastList: WinWindowList?

    /// Migawka dla wątku wejścia: prostokąty okien w pikselach monitora Windows.
    private let lock = NSLock()
    private var hitRects: [CGRect] = []
    private var displaySize = CGSize(width: 1, height: 1)
    /// Numery okien macOS pokazujących okna Windows (do sprawdzania, czy nie są zasłonięte).
    private var proxyNumbers: Set<Int> = []
    private var hostedNumbers: Set<Int> = []
    /// Strumienie przekazywane pomocnikom i okna, których Seam już nie dekoduje (pod `lock`).
    private var hostRoutes: [UInt32: WinHostConnection] = [:]
    private var hostedVisible: Set<UInt32> = []
    /// Najnowszy stan czekający na wątek główny (pod `lock`): lista okien, obrazy i kursor idą jednym
    /// przebiegiem, więc zajęty przez chwilę wątek główny nie odtwarza potem zaległych pozycji po kolei.
    private var pendingList: WinWindowList?
    private var pendingImages: [UInt32: WinStreamImage] = [:]
    private var pendingCursor: (point: CGPoint, shape: UInt8)?
    private var drainScheduled = false
    private var lastRelease = Date.distantPast
    private let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height

    init(screen: CGRect, key: Data, token: Data) {
        self.screen = screen
        receiver = WinViewReceiver(key: key, token: token)
    }

    func start(completion: @escaping (Result<UInt16, Error>) -> Void) {
        receiver.onFrame = { [weak self] frame in self?.decode(frame) }
        receiver.onClosed = { [weak self] reason in self?.onClosed?(reason) }
        receiver.onConnected = { [weak self] in self?.onKeyframeNeeded?() }
        proxies.onNumbersChanged = { [weak self] numbers in
            guard let self else { return }
            self.lock.withLock { self.proxyNumbers = Set(numbers.values) }
        }
        hosts.onKeyframeNeeded = { [weak self] in self?.requestKeyframe(force: true) }
        hosts.onRoutesChanged = { [weak self] in self?.routesChanged() }
        hosts.onActivateWindow = { [weak self] id in self?.onActivateWindow?(id) }
        hosts.onCloseWindows = { [weak self] ids in self?.onCloseWindows?(ids) }
        receiver.start(completion: completion)
    }

    func stop() {
        receiver.onFrame = nil
        receiver.onClosed = nil
        receiver.stop()
        // Usunięte dekodery zwalniają sesje VideoToolbox w deinit.
        decodeQueue.async { [weak self] in self?.decoders.removeAll() }
        let proxies = self.proxies, hosts = self.hosts
        DispatchQueue.main.async {
            hosts.stop()
            proxies.removeAll()
        }
        lock.withLock {
            hostRoutes = [:]
            hostedVisible = []
            hostedNumbers = []
            hitRects = []
            pendingList = nil
            pendingImages = [:]
            pendingCursor = nil
        }
    }

    var stats: (frames: UInt64, bytes: UInt64) { (receiver.framesReceived, receiver.bytesReceived) }

    var hasWindows: Bool { lock.withLock { !hitRects.isEmpty || !proxyNumbers.isEmpty || !hostedNumbers.isEmpty } }

    /// Nazwa i ikona aplikacji Windows (WINVIEW_APP).
    func app(_ info: WinAppInfo) {
        DispatchQueue.main.async { [weak self] in self?.hosts.setApp(info) }
    }

    // MARK: - Okna

    func update(_ list: WinWindowList) {
        let rects = list.windows.map { CGRect(x: CGFloat($0.x), y: CGFloat($0.y), width: CGFloat($0.width), height: CGFloat($0.height)) }
        let size = CGSize(width: list.displayWidth, height: list.displayHeight)
        lock.withLock {
            hitRects = rects
            displaySize = size
        }
        // Dekodery zamkniętych okien (były na liście, już ich nie ma) – nowy strumień o tym
        // samym id zacznie się od klatki kluczowej.
        let ids = Set(list.windows.map(\.id))
        decodeQueue.async { [weak self] in
            guard let self else { return }
            for id in self.listedIDs.subtracting(ids) { self.decoders[id] = nil }
            self.listedIDs = ids
        }
        // Położenie z listy od razu, bez czekania na obraz (lista jest pełna – liczy się tylko najnowsza).
        scheduleDrain { pendingList = list }
    }

    /// Okno Windows na Macu w tym punkcie jest widoczne (nie zasłania go okno innej aplikacji).
    private func proxyVisible(at point: CGPoint) -> Bool {
        let (numbers, hosted) = lock.withLock { (proxyNumbers, hostedNumbers) }
        guard !numbers.isEmpty || !hosted.isEmpty else { return false }
        let number = NSWindow.windowNumber(at: NSPoint(x: point.x, y: primaryHeight - point.y), belowWindowWithWindowNumber: 0)
        return numbers.contains(number) || hosted.contains(number)
    }

    /// Punkt ekranu Maca (globalne CG) → piksel monitora Windows, jeśli leży w którymś oknie Windows.
    func hitTest(_ point: CGPoint) -> (x: UInt16, y: UInt16)? {
        let hit: (x: UInt16, y: UInt16)? = lock.withLock {
            guard !hitRects.isEmpty, screen.contains(point) else { return nil }
            let px = CGPoint(x: (point.x - screen.minX) * displaySize.width / screen.width,
                             y: (point.y - screen.minY) * displaySize.height / screen.height)
            guard hitRects.contains(where: { $0.contains(px) }) else { return nil }
            return (UInt16(clamping: Int(px.x.rounded(.down))), UInt16(clamping: Int(px.y.rounded(.down))))
        }
        guard let hit, proxyVisible(at: point) else { return nil }
        return hit
    }

    /// Piksel monitora Windows → punkt ekranu Maca (globalne CG).
    func macPoint(x: UInt16, y: UInt16) -> CGPoint {
        let size = lock.withLock { displaySize }
        let point = CGPoint(x: screen.minX + (CGFloat(x) + 0.5) * screen.width / size.width,
                            y: screen.minY + (CGFloat(y) + 0.5) * screen.height / size.height)
        return CGPoint(x: min(max(point.x, screen.minX), screen.maxX - 1), y: min(max(point.y, screen.minY), screen.maxY - 1))
    }

    /// Kursor Windows jest na wirtualnym monitorze: pokazujemy kursor Maca w tym miejscu.
    func cursor(_ update: WinCursorUpdate) {
        let point = macPoint(x: update.x, y: update.y)
        if !update.buttons, !proxyVisible(at: point), Date().timeIntervalSince(lastRelease) > 0.3 {
            // Okno Windows jest tu zasłonięte przez okno Maca – kursor nie może zostać na
            // niewidocznym monitorze Windows.
            lastRelease = Date()
            onPointerRelease?(update.x, update.y)
        }
        scheduleDrain { pendingCursor = (point, update.shape) }
    }

    /// Aktywna aplikacja decyduje o kursorze – nad oknem Windows musi to być Seam.
    func pointerEntered() {
        DispatchQueue.main.async { [proxies, hosts] in
            // Okno aktywne na Windowsie pokazuje pomocnik: aktywna staje się ta aplikacja (pasek menu, Dock).
            if hosts.activateForeground() { return }
            // Kluczowe staje się okno Windows z bieżącego biurka: aktywacja z kluczowym oknem głównym
            // Seam przeniosłaby na biurko, na którym ono leży.
            proxies.makeFrontKey()
            NSApp.activate(ignoringOtherApps: true)
            proxies.bringToFront()
        }
    }

    /// Numer okna macOS pokazującego dane okno Windows (wątek główny; samotest).
    func proxyWindowNumber(_ id: UInt32) -> Int? { proxies.windowNumber(for: id) }

    /// Okno pokazywane przez pomocnika aplikacji (wątek główny; samotest).
    func hostedWindow(_ id: UInt32) -> (number: Int, pid: pid_t)? { hosts.hostedWindow(id) }

    // MARK: - Obraz

    private func decode(_ frame: VideoStream.Frame) {
        guard frame.kind == .windowAccessUnit else { return }
        decodeQueue.async { [weak self] in
            guard let self else { return }
            let id = frame.streamID
            let (host, hosted) = self.lock.withLock { (self.hostRoutes[id], self.hostedVisible.contains(id)) }
            if let host { self.forward(frame, to: host) }
            if hosted {
                // Okno pokazuje pomocnik; gdyby wróciło do Seam, dekoder zacznie od klatki kluczowej.
                self.decoders[id] = nil
                return
            }
            let decoder: H264Decompressor
            if let existing = self.decoders[id] {
                decoder = existing
            } else {
                // Strumień okna zaczyna się od klatki kluczowej – do tego czasu nie ma czego dekodować.
                guard frame.isKeyframe else {
                    self.requestKeyframe()
                    return
                }
                decoder = H264Decompressor()
                self.decoders[id] = decoder
            }
            do {
                guard let buffer = try decoder.decode(frame.payload),
                      let surface = CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue() else { return }
                self.deliver(id, WinStreamImage(buffer: buffer, surface: surface, width: frame.width, height: frame.height,
                                                cornerRadius: frame.cornerRadius))
            } catch {
                self.decoders[id] = nil
                self.requestKeyframe()
            }
        }
    }

    /// Na wątek główny trafia tylko najnowszy obraz każdego okna – zablokowany wątek
    /// główny nie odtwarza potem zaległych klatek.
    private func deliver(_ id: UInt32, _ image: WinStreamImage) {
        scheduleDrain { pendingImages[id] = image }
    }

    /// Dowolny wątek: zmiana stanu pod blokadą i najwyżej jeden czekający przebieg na wątku głównym.
    private func scheduleDrain(_ change: () -> Void) {
        let schedule: Bool = lock.withLock {
            change()
            guard !drainScheduled else { return false }
            drainScheduled = true
            return true
        }
        guard schedule else { return }
        DispatchQueue.main.async { [weak self] in self?.drain() }
    }

    /// Wątek główny: najpierw lista (nowe okna, położenie), potem obrazy, na końcu kursor – w jednej transakcji,
    /// żeby okno i kursor przesuwały się razem.
    private func drain() {
        let (list, images, cursor) = lock.withLock { () -> (WinWindowList?, [UInt32: WinStreamImage], (point: CGPoint, shape: UInt8)?) in
            defer {
                pendingList = nil
                pendingImages = [:]
                pendingCursor = nil
                drainScheduled = false
            }
            return (pendingList, pendingImages, pendingCursor)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let list {
            lastList = list
            hosts.update(list, screen: screen)
            proxies.update(localWindows(list), screen: screen)
        }
        proxies.show(images)
        CATransaction.commit()
        if let cursor {
            CGWarpMouseCursorPosition(cursor.point)
            // Kształt kursora ustawia aktywna aplikacja – Seam albo pomocnik.
            if !hosts.setCursor(cursor.shape) { NSCursor.winView(cursor.shape).set() }
        }
    }

    /// Okna, których nie pokazuje żaden pomocnik (wątek główny).
    private func localWindows(_ list: WinWindowList) -> WinWindowList {
        let hosted = hosts.hostedVisible
        guard !hosted.isEmpty else { return list }
        return WinWindowList(displayWidth: list.displayWidth, displayHeight: list.displayHeight,
                             windows: list.windows.filter { !hosted.contains($0.id) })
    }

    /// Wątek główny: pomocnik ruszył, pokazał okno albo zakończył pracę.
    private func routesChanged() {
        let routes = hosts.routes, hosted = hosts.hostedVisible, numbers = hosts.hostedNumbers
        lock.withLock {
            hostRoutes = routes
            hostedVisible = hosted
            hostedNumbers = numbers
        }
        guard let list = lastList else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        proxies.update(localWindows(list), screen: screen)
        CATransaction.commit()
    }

    /// Kolejka dekodera: klatka dla pomocnika. Pominięta (pomocnik nie nadąża) – następna musi być kluczowa.
    private func forward(_ frame: VideoStream.Frame, to host: WinHostConnection) {
        var w = ByteWriter()
        w.u32(frame.streamID)
        w.u8(frame.isKeyframe ? 1 : 0)
        w.u16(UInt16(clamping: frame.width))
        w.u16(UInt16(clamping: frame.height))
        w.u16(frame.cornerRadius)
        w.raw([UInt8](frame.payload))
        if !host.send(.frame, w.bytes, droppable: !frame.isKeyframe) { requestKeyframe() }
    }

    /// Dowolny wątek (`force`: bez odstępu – nowy pomocnik).
    private func requestKeyframe(force: Bool = false) {
        let now = Date()
        let due: Bool = lock.withLock {
            guard force || now.timeIntervalSince(lastKeyframeRequest) > 0.5 else { return false }
            lastKeyframeRequest = now
            return true
        }
        guard due else { return }
        onKeyframeNeeded?()
    }
}
