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

    private let receiver: WinViewReceiver
    private let decodeQueue = DispatchQueue(label: "blm.winview.decode", qos: .userInteractive)
    /// Kolejka dekodera: dekoder dla każdego strumienia okna.
    private var decoders: [UInt32: H264Decompressor] = [:]
    private var listedIDs: Set<UInt32> = []
    private var lastKeyframeRequest = Date.distantPast
    private let proxies = WinWindowProxies()

    /// Migawka dla wątku wejścia: prostokąty okien w pikselach monitora Windows.
    private let lock = NSLock()
    private var hitRects: [CGRect] = []
    private var displaySize = CGSize(width: 1, height: 1)
    /// Numery okien macOS pokazujących okna Windows (do sprawdzania, czy nie są zasłonięte).
    private var proxyNumbers: Set<Int> = []
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
            self.lock.withLock { self.proxyNumbers = numbers }
        }
        receiver.start(completion: completion)
    }

    func stop() {
        receiver.onFrame = nil
        receiver.onClosed = nil
        receiver.stop()
        // Usunięte dekodery zwalniają sesje VideoToolbox w deinit.
        decodeQueue.async { [weak self] in self?.decoders.removeAll() }
        let proxies = self.proxies
        DispatchQueue.main.async { proxies.removeAll() }
        lock.withLock {
            hitRects = []
            pendingList = nil
            pendingImages = [:]
            pendingCursor = nil
        }
    }

    var stats: (frames: UInt64, bytes: UInt64) { (receiver.framesReceived, receiver.bytesReceived) }

    var hasWindows: Bool { lock.withLock { !hitRects.isEmpty || !proxyNumbers.isEmpty } }

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
        let numbers = lock.withLock { proxyNumbers }
        guard !numbers.isEmpty else { return false }
        let number = NSWindow.windowNumber(at: NSPoint(x: point.x, y: primaryHeight - point.y), belowWindowWithWindowNumber: 0)
        return numbers.contains(number)
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
        DispatchQueue.main.async { [proxies] in
            // Kluczowe staje się okno Windows z bieżącego biurka: aktywacja z kluczowym oknem głównym
            // Seam przeniosłaby na biurko, na którym ono leży.
            proxies.makeFrontKey()
            NSApp.activate(ignoringOtherApps: true)
            proxies.bringToFront()
        }
    }

    /// Numer okna macOS pokazującego dane okno Windows (wątek główny; samotest).
    func proxyWindowNumber(_ id: UInt32) -> Int? { proxies.windowNumber(for: id) }

    private static func cursor(for shape: UInt8) -> NSCursor {
        switch CursorTracker.Shape(rawValue: shape) {
        case .iBeam: return .iBeam
        case .pointingHand: return .pointingHand
        case .resizeLeftRight: return .resizeLeftRight
        case .resizeUpDown: return .resizeUpDown
        case .crosshair: return .crosshair
        case .notAllowed: return .operationNotAllowed
        case .openHand: return .openHand
        case .closedHand: return .closedHand
        case .resizeDiagonalDown:
            if #available(macOS 15.0, *) { return .frameResize(position: .topLeft, directions: .all) }
            return .crosshair
        case .resizeDiagonalUp:
            if #available(macOS 15.0, *) { return .frameResize(position: .topRight, directions: .all) }
            return .crosshair
        default: return .arrow
        }
    }

    // MARK: - Obraz

    private func decode(_ frame: VideoStream.Frame) {
        guard frame.kind == .windowAccessUnit else { return }
        decodeQueue.async { [weak self] in
            guard let self else { return }
            let id = frame.streamID
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
        if let list { proxies.update(list, screen: screen) }
        proxies.show(images)
        CATransaction.commit()
        if let cursor {
            CGWarpMouseCursorPosition(cursor.point)
            WinViewSession.cursor(for: cursor.shape).set()
        }
    }

    /// Kolejka dekodera.
    private func requestKeyframe() {
        guard Date().timeIntervalSince(lastKeyframeRequest) > 0.5 else { return }
        lastKeyframeRequest = Date()
        onKeyframeNeeded?()
    }
}

/// Zdekodowany obraz okna Windows: `width`×`height` to treść w lewym górnym rogu bufora
/// (bufor ma rozmiar „kubełka”, wielokrotność 64).
struct WinStreamImage {
    let buffer: CVPixelBuffer
    let surface: IOSurfaceRef
    let width: Int
    let height: Int
    /// Promień rogów w pikselach monitora Windows (0 = proste rogi).
    let cornerRadius: UInt16
}

/// Okna macOS pokazujące okna Windows (wątek główny).
final class WinWindowProxies {
    /// Okno pokazujące okno Windows. Może być kluczowe (wtedy aktywacja Seam nie przenosi na biurko
    /// z oknem głównym), ale klawiszy z klawiatury Maca nie obsługuje – pisze się w Windowsie.
    private final class ProxyWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
        override func keyDown(with event: NSEvent) {}
    }

    private final class Proxy {
        let window: NSWindow
        /// Jedna warstwa z obrazem strumienia okna, przycięta do rogów okna.
        let content = CALayer()
        var descriptor: WinWindowDescriptor
        var image: WinStreamImage?
        /// Ma obraz i leży (choć częściowo) na monitorze Windows.
        var shown = false

        init(descriptor: WinWindowDescriptor) {
            self.descriptor = descriptor
            window = ProxyWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = !descriptor.isPopup
            window.level = descriptor.isPopup ? .popUpMenu : .normal
            // Monitor Windows odpowiada ekranowi Maca, a nie jednemu biurku: okna Windows są na każdym biurku.
            // Inaczej wysunięcie okna (aktywne na Windowsie, nowe okno) przełączałoby na biurko, na którym powstało.
            window.collectionBehavior = [.managed, .canJoinAllSpaces, .fullScreenNone]
            window.animationBehavior = .none
            let view = NSView()
            view.wantsLayer = true
            window.contentView = view
            content.masksToBounds = true
            content.backgroundColor = NSColor.clear.cgColor
            content.contentsGravity = .resize
            content.magnificationFilter = .linear
            content.minificationFilter = .linear
            content.actions = ["contents": NSNull(), "contentsRect": NSNull(), "contentsScale": NSNull(),
                               "position": NSNull(), "bounds": NSNull(), "frame": NSNull(), "cornerRadius": NSNull()]
            view.layer?.addSublayer(content)
        }
    }

    private var proxies: [UInt32: Proxy] = [:]
    /// Obrazy strumieni, także tych, których okna lista jeszcze nie zawiera.
    private var images: [UInt32: WinStreamImage] = [:]
    /// Kolejność od najwyższego (jak na Windowsie).
    private var order: [UInt32] = []
    private var displaySize = CGSize(width: 1, height: 1)
    private var screen = CGRect.zero
    /// Skala ekranu Maca (piksele na punkt) – do zaokrąglania ramek do siatki pikseli.
    private var scale: CGFloat = 2
    private var foreground: UInt32?
    /// Wywoływane po zmianie zbioru okien (wątek główny).
    var onNumbersChanged: ((Set<Int>) -> Void)?
    /// Aplikacja była tylko w pasku menu – dopóki są okna Windows, ma ikonę w Docku i w Cmd+Tab.
    private var promotedToRegular = false
    private var activationObserver: NSObjectProtocol?

    init() {
        // Kliknięcie ikony w Docku / Cmd+Tab wyciąga okna Windows spod okien innych aplikacji.
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                                    object: nil, queue: .main) { [weak self] _ in
            self?.bringToFront()
        }
    }

    deinit {
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    }

    private func publishNumbers() {
        onNumbersChanged?(Set(proxies.values.filter { $0.window.isVisible }.map(\.window.windowNumber)))
        if !proxies.isEmpty, NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            promotedToRegular = true
        } else if proxies.isEmpty, promotedToRegular {
            promotedToRegular = false
            if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) { NSApp.setActivationPolicy(.accessory) }
        }
    }

    func update(_ list: WinWindowList, screen: CGRect) {
        self.screen = screen
        scale = Self.backingScale(for: screen)
        displaySize = CGSize(width: list.displayWidth, height: list.displayHeight)
        let ids = list.windows.map(\.id)
        let listed = Set(ids)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (id, proxy) in proxies where !listed.contains(id) {
            proxy.window.orderOut(nil)
            proxies[id] = nil
            images[id] = nil
        }
        // Obrazy strumieni spoza listy nie mogą się gromadzić bez końca.
        if images.count > 64 { images = images.filter { listed.contains($0.key) } }
        var created = false
        var appeared = false
        for descriptor in list.windows {
            let proxy: Proxy
            if let existing = proxies[descriptor.id] {
                proxy = existing
                proxy.descriptor = descriptor
            } else {
                proxy = Proxy(descriptor: descriptor)
                proxy.image = images[descriptor.id]
                proxies[descriptor.id] = proxy
                created = true
            }
            if layout(proxy) { appeared = true }
            if proxy.window.title != descriptor.title { proxy.window.title = descriptor.title }
        }
        let newForeground = list.windows.first(where: \.isForeground)?.id
        let reordered = ids != order
        order = ids
        if created || appeared || reordered || (newForeground != nil && newForeground != foreground) {
            // Okno aktywne na Windowsie (kliknięte, nowe) – cała grupa wychodzi na wierzch Maca.
            restack(bringToFront: created || newForeground != foreground)
        }
        CATransaction.commit()
        foreground = newForeground
        publishNumbers()
    }

    /// Najnowsze obrazy strumieni okien.
    func show(_ updates: [UInt32: WinStreamImage]) {
        guard !updates.isEmpty else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var appeared = false
        for (id, image) in updates {
            images[id] = image
            guard let proxy = proxies[id] else { continue }
            proxy.image = image
            if layout(proxy) { appeared = true }
        }
        // Pierwszy obraz okna (nowe okno, menu) – grupa wychodzi na wierzch jak na Windowsie.
        if appeared { restack(bringToFront: true) }
        CATransaction.commit()
        if appeared { publishNumbers() }
    }

    func bringToFront() { restack(bringToFront: true) }

    /// Najwyższe widoczne okno Windows staje się kluczowe (przed aktywacją Seam).
    func makeFrontKey() {
        guard let id = order.first(where: { proxies[$0]?.shown == true }), let proxy = proxies[id] else { return }
        proxy.window.makeKey()
    }

    func windowNumber(for id: UInt32) -> Int? { proxies[id]?.window.windowNumber }

    func removeAll() {
        for proxy in proxies.values { proxy.window.orderOut(nil) }
        proxies = [:]
        images = [:]
        order = []
        foreground = nil
        publishNumbers()
    }

    private func restack(bringToFront: Bool) {
        // Od najniższego do najwyższego: każde kolejne nad poprzednim. Okna bez obrazu czekają ukryte.
        var below: Int?
        for id in order.reversed() {
            guard let proxy = proxies[id], proxy.shown else { continue }
            if let below {
                proxy.window.order(.above, relativeTo: below)
            } else if bringToFront || !proxy.window.isVisible {
                proxy.window.orderFrontRegardless()
            } else {
                proxy.window.orderFront(nil)
            }
            below = proxy.window.windowNumber
        }
    }

    private func snap(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }

    /// Ramka okna z listy i wycinek obrazu. Zwraca true, gdy okno trzeba (ponownie) pokazać.
    /// Wywoływać wewnątrz transakcji z wyłączonymi animacjami.
    @discardableResult
    private func layout(_ proxy: Proxy) -> Bool {
        let d = proxy.descriptor
        let full = CGRect(x: CGFloat(d.x), y: CGFloat(d.y), width: CGFloat(d.width), height: CGFloat(d.height))
        // Część okna poza monitorem Windows nie może wyjść poza ekran Maca.
        let visible = full.intersection(CGRect(origin: .zero, size: displaySize))
        guard let image = proxy.image, !visible.isNull, visible.width > 0, visible.height > 0 else {
            proxy.shown = false
            if proxy.window.isVisible { proxy.window.orderOut(nil) }
            return false
        }
        let sx = screen.width / displaySize.width, sy = screen.height / displaySize.height
        // Krawędzie w globalnych CG (y w dół), zaokrąglone do pikseli ekranu – obraz bez przeskalowania.
        let left = snap(screen.minX + visible.minX * sx), right = snap(screen.minX + visible.maxX * sx)
        let top = snap(screen.minY + visible.minY * sy), bottom = snap(screen.minY + visible.maxY * sy)
        // Globalne CG → AppKit (y w górę od dołu ekranu głównego).
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.maxY
        let minSide = 1 / scale
        let frame = CGRect(x: left, y: primaryHeight - bottom, width: max(right - left, minSide), height: max(bottom - top, minSide))
        if proxy.window.frame != frame { proxy.window.setFrame(frame, display: false) }

        let layer = proxy.content
        layer.frame = CGRect(origin: .zero, size: frame.size)
        layer.contentsScale = scale
        layer.contents = image.surface
        // Wycinek w pikselach treści (y w dół od lewego górnego rogu); treść może mieć chwilowo
        // inny rozmiar niż okno z listy (zmiana rozmiaru) – wtedy jest skalowana.
        let kx = CGFloat(image.width) / full.width, ky = CGFloat(image.height) / full.height
        let bufferWidth = CGFloat(CVPixelBufferGetWidth(image.buffer))
        let bufferHeight = CGFloat(CVPixelBufferGetHeight(image.buffer))
        let crop = CGRect(x: (visible.minX - full.minX) * kx, y: (visible.minY - full.minY) * ky,
                          width: visible.width * kx, height: visible.height * ky)
            .intersection(CGRect(x: 0, y: 0, width: bufferWidth, height: bufferHeight))
        // contentsRect jest w jednostkach obrazu w układzie warstwy; warstwa AppKit nie jest
        // odwrócona (y w górę), więc y = 0 to DÓŁ bufora, a treść z jego lewego górnego rogu
        // zaczyna się na y = 1 - (dół wycinka) / wysokość bufora.
        if !crop.isNull, bufferWidth > 0, bufferHeight > 0 {
            layer.contentsRect = CGRect(x: crop.minX / bufferWidth, y: 1 - crop.maxY / bufferHeight,
                                        width: crop.width / bufferWidth, height: crop.height / bufferHeight)
        }
        layer.cornerRadius = CGFloat(image.cornerRadius) * sx

        let appeared = !proxy.shown || !proxy.window.isVisible
        proxy.shown = true
        return appeared
    }

    /// Skala (backingScaleFactor) ekranu Maca o podanych granicach w globalnych CG.
    private static func backingScale(for bounds: CGRect) -> CGFloat {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            if CGDisplayBounds(CGDirectDisplayID(number.uint32Value)) == bounds { return screen.backingScaleFactor }
        }
        return NSScreen.main?.backingScaleFactor ?? 2
    }
}
