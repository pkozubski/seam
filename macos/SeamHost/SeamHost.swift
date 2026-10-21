import AppKit
import CoreVideo
import QuartzCore

/// Pomocnik jednej aplikacji Windows: osobny proces z pakietem o nazwie i ikonie tej aplikacji,
/// więc na Macu ma własną ikonę w Docku, wpis w Cmd+Tab i nazwę w pasku menu. Pokazuje okna tej
/// aplikacji – Seam przekazuje ich położenie i strumień H.264 przez gniazdo Unix (`WinHostLink`).
/// Mysz i klawiatura nad oknami nadal idą do Windowsa (obsługuje je Seam).
@main
enum SeamHostMain {
    static func main() {
        var options: [String: String] = [:]
        let args = CommandLine.arguments
        var index = 1
        while index + 1 < args.count {
            if args[index].hasPrefix("--seam-") { options[args[index]] = args[index + 1] }
            index += 2
        }
        // Uruchomiony bez Seam (np. z Docka po zakończeniu) – nie ma czego pokazać.
        guard let path = options["--seam-socket"], let tokenHex = options["--seam-token"], let key = options["--seam-key"],
              let token = bytes(hex: tokenHex), token.count == 16,
              let connection = WinHostConnection.connect(path: path) else { exit(0) }
        let app = NSApplication.shared
        let delegate = HostDelegate(connection: connection, token: token, key: key)
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }

    private static func bytes(hex: String) -> [UInt8]? {
        let chars = Array(hex.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let byte = UInt8(String(decoding: chars[i..<(i + 2)], as: UTF8.self), radix: 16) else { return nil }
            out.append(byte)
        }
        return out
    }
}

final class HostDelegate: NSObject, NSApplicationDelegate {
    private let connection: WinHostConnection
    private let token: [UInt8]
    private let key: String
    private let proxies = WinWindowProxies()
    private let decodeQueue = DispatchQueue(label: "seam.host.decode", qos: .userInteractive)
    /// Kolejka dekodera.
    private var decoders: [UInt32: H264Decompressor] = [:]
    private var listed: Set<UInt32> = []

    private let lock = NSLock()
    private var pendingImages: [UInt32: WinStreamImage] = [:]
    private var pendingLayout: (screen: CGRect, list: WinWindowList)?
    private var drainScheduled = false
    private var lastKeyframeRequest = Date.distantPast

    /// Wątek główny.
    private var screen = CGRect.zero
    private var quitBySeam = false
    private var activatedBySeamAt = Date.distantPast

    init(connection: WinHostConnection, token: [UInt8], key: String) {
        self.connection = connection
        self.token = token
        self.key = key
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? ProcessInfo.processInfo.processName
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        proxies.onNumbersChanged = { [connection] numbers in
            var w = ByteWriter()
            let visible = numbers.prefix(255)
            w.u8(UInt8(visible.count))
            for (id, number) in visible {
                w.u32(id)
                w.u32(UInt32(truncatingIfNeeded: number))
            }
            connection.send(.numbers, w.bytes)
        }
        connection.onMessage = { [weak self] type, payload in self?.received(type, payload) }
        connection.onClosed = {
            DispatchQueue.main.async { [weak self] in
                // Seam zakończył pracę albo zerwał łącze – bez niego okna nie mają treści.
                self?.quitBySeam = true
                NSApp.terminate(nil)
            }
        }
        connection.start()
        var hello = ByteWriter()
        hello.raw(token)
        hello.u32(UInt32(bitPattern: getpid()))
        hello.string(key)
        connection.send(.hello, hello.bytes)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Dock, Cmd+Tab, kliknięcie paska menu – Windows ma aktywować okno tej aplikacji.
        guard Date().timeIntervalSince(activatedBySeamAt) > 1 else { return }
        var w = ByteWriter()
        w.u32(0)
        connection.send(.activated, w.bytes)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        proxies.bringToFront()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitBySeam { return .terminateNow }
        // Wylogowanie, restart, wyłączenie: nie zamykamy aplikacji na Windowsie.
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           event.attributeDescriptor(forKeyword: 0x7768_793F /* 'why?' kAEQuitReason */) != nil {
            return .terminateNow
        }
        // „Zakończ”: Windows zamyka okna jak przyciskiem ×. Pomocnik kończy pracę, gdy okna znikną –
        // jeśli aplikacja zapyta o zapis, pytanie pojawi się w tej samej aplikacji.
        connection.send(.closeRequested)
        return .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        connection.flush()
        connection.close()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let windows = proxies.titledWindows
        guard !windows.isEmpty else { return nil }
        let menu = NSMenu()
        for window in windows {
            let item = NSMenuItem(title: window.title.isEmpty ? appName : window.title,
                                  action: #selector(showWindow(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(window.id)
            menu.addItem(item)
        }
        return menu
    }

    @objc private func showWindow(_ sender: NSMenuItem) {
        let id = UInt32(truncatingIfNeeded: sender.tag)
        proxies.bringToFront(id)
        activatedBySeamAt = Date()
        NSApp.activate(ignoringOtherApps: true)
        var w = ByteWriter()
        w.u32(id)
        connection.send(.activated, w.bytes)
    }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: appName)
        appMenu.addItem(withTitle: L10n.text("Ukryj \(appName)", "Hide \(appName)"),
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = appMenu.addItem(withTitle: L10n.text("Ukryj pozostałe", "Hide Others"),
                                     action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: L10n.text("Pokaż wszystkie", "Show All"),
                        action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.text("Zakończ \(appName)", "Quit \(appName)"),
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        return main
    }

    // MARK: - Łącze (kolejka gniazda)

    private func received(_ type: WinHostMessage, _ payload: [UInt8]) {
        switch type {
        case .layout:
            var r = ByteReader(payload)
            var values: [CGFloat] = []
            for _ in 0..<4 {
                guard let bits = r.u64() else { return }
                values.append(CGFloat(Double(bitPattern: bits)))
            }
            guard let rest = r.bytes(r.remaining), let list = WinWindowList(payload: rest) else { return }
            let screen = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
            let ids = Set(list.windows.map(\.id))
            decodeQueue.async { [weak self] in
                guard let self else { return }
                for id in self.listed.subtracting(ids) { self.decoders[id] = nil }
                self.listed = ids
            }
            scheduleDrain { pendingLayout = (screen, list) }
        case .frame:
            var r = ByteReader(payload)
            guard let id = r.u32(), let keyframe = r.u8(), let width = r.u16(), let height = r.u16(),
                  let radius = r.u16(), let data = r.bytes(r.remaining) else { return }
            decode(id: id, keyframe: keyframe != 0, width: Int(width), height: Int(height), cornerRadius: radius, data: Data(data))
        case .cursor:
            guard let shape = payload.first else { return }
            DispatchQueue.main.async { NSCursor.winView(shape).set() }
        case .activate:
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.activatedBySeamAt = Date()
                self.proxies.makeFrontKey()
                NSApp.activate(ignoringOtherApps: true)
                self.proxies.bringToFront()
            }
        case .quit:
            DispatchQueue.main.async { [weak self] in
                self?.quitBySeam = true
                NSApp.terminate(nil)
            }
        default:
            break
        }
    }

    // MARK: - Obraz

    private func decode(id: UInt32, keyframe: Bool, width: Int, height: Int, cornerRadius: UInt16, data: Data) {
        decodeQueue.async { [weak self] in
            guard let self else { return }
            let decoder: H264Decompressor
            if let existing = self.decoders[id] {
                decoder = existing
            } else {
                guard keyframe else {
                    self.requestKeyframe()
                    return
                }
                decoder = H264Decompressor()
                self.decoders[id] = decoder
            }
            do {
                guard let buffer = try decoder.decode(data),
                      let surface = CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue() else { return }
                let image = WinStreamImage(buffer: buffer, surface: surface, width: width, height: height, cornerRadius: cornerRadius)
                self.scheduleDrain { self.pendingImages[id] = image }
            } catch {
                self.decoders[id] = nil
                self.requestKeyframe()
            }
        }
    }

    private func requestKeyframe() {
        let now = Date()
        let due: Bool = lock.withLock {
            guard now.timeIntervalSince(lastKeyframeRequest) > 0.5 else { return false }
            lastKeyframeRequest = now
            return true
        }
        if due { connection.send(.keyframe) }
    }

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

    /// Wątek główny: najnowsze położenie, potem obrazy – w jednej transakcji.
    private func drain() {
        let (layout, images) = lock.withLock { () -> ((screen: CGRect, list: WinWindowList)?, [UInt32: WinStreamImage]) in
            defer {
                pendingLayout = nil
                pendingImages = [:]
                drainScheduled = false
            }
            return (pendingLayout, pendingImages)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let layout {
            screen = layout.screen
            proxies.update(layout.list, screen: layout.screen)
        }
        proxies.show(images)
        CATransaction.commit()
    }
}
