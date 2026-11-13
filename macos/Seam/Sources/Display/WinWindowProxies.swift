import AppKit
import CoreVideo
import QuartzCore

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
    /// Wywoływane po zmianie zbioru okien (wątek główny): widoczne okna, id okna Windows → numer okna macOS.
    var onNumbersChanged: (([UInt32: Int]) -> Void)?
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
        var numbers: [UInt32: Int] = [:]
        for (id, proxy) in proxies where proxy.window.isVisible { numbers[id] = proxy.window.windowNumber }
        onNumbersChanged?(numbers)
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

    /// Najwyższe widoczne okno (nie menu) – to je aktywuje Windows po wybraniu aplikacji w Docku.
    var topWindowID: UInt32? {
        order.first { proxies[$0]?.shown == true && proxies[$0]?.descriptor.isPopup == false }
    }

    /// Widoczne okna (nie menu) od najwyższego: id i tytuł – do menu Docka.
    var titledWindows: [(id: UInt32, title: String)] {
        order.compactMap { id in
            guard let proxy = proxies[id], proxy.shown, !proxy.descriptor.isPopup else { return nil }
            return (id, proxy.descriptor.title)
        }
    }

    /// Wyciąga jedno okno nad pozostałe (menu Docka); kolejność z Windows przyjdzie z następną listą.
    func bringToFront(_ id: UInt32) {
        guard let proxy = proxies[id], proxy.shown else { return }
        proxy.window.orderFrontRegardless()
        proxy.window.makeKey()
    }

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

extension NSCursor {
    /// Kształt kursora Windows (numeracja CURSOR_SHAPE, jak `CursorTracker.Shape`).
    static func winView(_ shape: UInt8) -> NSCursor {
        switch shape {
        case 1: return .iBeam
        case 2: return .pointingHand
        case 3: return .resizeLeftRight
        case 4: return .resizeUpDown
        case 5: return .crosshair
        case 6: return .operationNotAllowed
        case 7: return .openHand
        case 8: return .closedHand
        case 9:
            if #available(macOS 15.0, *) { return .frameResize(position: .topLeft, directions: .all) }
            return .crosshair
        case 10:
            if #available(macOS 15.0, *) { return .frameResize(position: .topRight, directions: .all) }
            return .crosshair
        default: return .arrow
        }
    }
}
