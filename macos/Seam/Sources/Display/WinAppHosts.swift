import AppKit
import CryptoKit
import Foundation

/// Pakiety aplikacji-pomocników: każda aplikacja Windows dostaje na Macu własny pakiet `.app`
/// (nazwa i ikona z Windowsa, własny identyfikator), więc ma osobną ikonę w Docku, wpis w Cmd+Tab
/// i nazwę w pasku menu – jak natywna aplikacja. Plik wykonywalny to `SeamHost` z pakietu Seam.
enum WinAppBundles {
    /// `Seam.app/Contents/Helpers/SeamHost`.
    static var hostExecutable: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/SeamHost")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    static var isAvailable: Bool { hostExecutable != nil }

    /// `.noindex`: Spotlight i Launchpad nie pokazują pomocników jako aplikacji do uruchomienia.
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Seam/Windows Apps.noindex", isDirectory: true)
    }

    /// Klucz aplikacji (nazwa exe) → bezpieczny fragment identyfikatora i nazwy katalogu.
    static func sanitizedKey(_ key: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        let mapped = String(key.lowercased().map { allowed.contains($0) ? $0 : "-" }.prefix(60))
        let trimmed = mapped.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "app" : trimmed
    }

    static func bundleIdentifier(for key: String) -> String { "com.borderlessmouse.winapp.\(sanitizedKey(key))" }

    private static func displayName(_ info: WinAppInfo) -> String {
        let cleaned = info.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty, !cleaned.hasPrefix(".") { return String(cleaned.prefix(60)) }
        return info.key.isEmpty ? "Windows" : String(info.key.prefix(60))
    }

    /// Gotowy pakiet dla aplikacji (tworzy go albo odświeża po zmianie Seam, nazwy lub ikony). Wolne: nie na wątku głównym.
    static func prepare(_ info: WinAppInfo) throws -> URL {
        guard let host = hostExecutable else { throw CocoaError(.fileNoSuchFile) }
        let fm = FileManager.default
        let folder = directory.appendingPathComponent(sanitizedKey(info.key), isDirectory: true)
        let name = displayName(info)
        let bundle = folder.appendingPathComponent("\(name).app", isDirectory: true)
        let stamp = Self.stamp(info, host: host, name: name)
        let plistURL = bundle.appendingPathComponent("Contents/Info.plist")
        if let data = try? Data(contentsOf: plistURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           plist["SeamHostStamp"] as? String == stamp,
           fm.isExecutableFile(atPath: bundle.appendingPathComponent("Contents/MacOS/SeamHost").path) {
            return bundle
        }

        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        // Budowa obok i podmiana na końcu: działająca kopia zachowuje swoje pliki (inne i-węzły).
        let staging = folder.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        let staged = staging.appendingPathComponent("\(name).app", isDirectory: true)
        let macOS = staged.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let resources = staged.appendingPathComponent("Contents/Resources", isDirectory: true)
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        try fm.copyItem(at: host, to: macOS.appendingPathComponent("SeamHost"))
        try icns(from: info.icon).write(to: resources.appendingPathComponent("AppIcon.icns"))
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let plist: [String: Any] = [
            "CFBundleExecutable": "SeamHost",
            "CFBundleIdentifier": bundleIdentifier(for: info.key),
            "CFBundleName": name,
            "CFBundleDisplayName": name,
            "CFBundlePackageType": "APPL",
            "CFBundleIconFile": "AppIcon",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build,
            "LSMinimumSystemVersion": "14.2",
            "NSHighResolutionCapable": true,
            "NSPrincipalClass": "NSApplication",
            "NSSupportsAutomaticTermination": false,
            "NSSupportsSuddenTermination": false,
            "NSHumanReadableCopyright": "Windows · Seam",
            "SeamHostStamp": stamp,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: staged.appendingPathComponent("Contents/Info.plist"))
        try Data("APPL????".utf8).write(to: staged.appendingPathComponent("Contents/PkgInfo"))
        // Podpis ad hoc pieczętuje nowy Info.plist (kopia podpisu Seam dotyczy innego pakietu).
        sign(staged)

        // Stare pakiety tej aplikacji (np. po zmianie nazwy) znikają.
        for old in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        where old.pathExtension == "app" {
            try? fm.removeItem(at: old)
        }
        try fm.moveItem(at: staged, to: bundle)
        LSRegisterURL(bundle as CFURL, true)
        return bundle
    }

    private static func stamp(_ info: WinAppInfo, host: URL, name: String) -> String {
        let attributes = (try? FileManager.default.attributesOfItem(atPath: host.path)) ?? [:]
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let modified = Int((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
        let icon = SHA256.hash(data: Data(info.icon)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "3-\(version)-\(size)-\(modified)-\(icon)-\(name)"
    }

    private static func sign(_ bundle: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--sign", "-", "--timestamp=none", bundle.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // bez podpisu pakiet zwykle i tak się uruchomi (pliki nie mają kwarantanny)
        }
    }

    /// Ikona Windows (PNG) w siatce ikon macOS: ikony Windows wypełniają cały kwadrat, a ikony
    /// Maca mają margines – bez niego ikona w Docku byłaby większa od sąsiednich.
    static func icns(from png: [UInt8]) throws -> Data {
        let source = png.isEmpty ? nil : NSImage(data: Data(png))
        let image = source ?? NSWorkspace.shared.icon(for: .application)
        let out = NSMutableData()
        let sizes = [32, 64, 128, 256, 512]
        guard let destination = CGImageDestinationCreateWithData(out, "com.apple.icns" as CFString, sizes.count, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        for size in sizes {
            guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            context.interpolationQuality = .high
            let inset = source == nil ? 0 : CGFloat(size) * 0.1
            let rect = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: inset, dy: inset)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            if let cgImage = context.makeImage() { CGImageDestinationAddImage(destination, cgImage, nil) }
        }
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return out as Data
    }
}

/// Pomocnicy aplikacji Windows (wątek główny): uruchamianie, łącze, podział okien między
/// pomocników a okna w samym Seam (gdy pomocnik jeszcze nie działa albo się nie udał).
final class WinAppHosts {
    private final class Host {
        let key: String
        var info: WinAppInfo
        var connection: WinHostConnection?
        var process: NSRunningApplication?
        let launchedAt = Date()
        var windowIDs: [UInt32] = []
        /// Okna, które pomocnik już pokazuje (id → numer okna macOS).
        var visible: [UInt32: Int] = [:]
        var emptySince: Date?
        var lastLayout: [UInt8] = []
        /// Ostatnia aktywacja na prośbę Seam – nie odsyłamy jej do Windowsa.
        var activatedBySeamAt = Date.distantPast

        init(key: String, info: WinAppInfo) {
            self.key = key
            self.info = info
        }
    }

    /// Okna pokazywane przez pomocników albo strumienie do nich – zmienione (wątek główny).
    var onRoutesChanged: (() -> Void)?
    var onKeyframeNeeded: (() -> Void)?
    /// Użytkownik wybrał aplikację na Macu – Windows ma aktywować to okno.
    var onActivateWindow: ((UInt32) -> Void)?
    /// Zakończ w Docku – Windows ma zamknąć te okna.
    var onCloseWindows: (([UInt32]) -> Void)?

    private var hosts: [String: Host] = [:]
    private var apps: [UInt32: WinAppInfo] = [:]
    /// Pomocnik się nie uruchomił – okna tej aplikacji zostają w Seam do tego czasu.
    private var retryAfter: [String: Date] = [:]
    /// Po „Zakończ” okna znikają; jeśli zostaną (np. pytanie o zapis), pomocnik wróci po tym czasie.
    private var closingUntil: [String: Date] = [:]
    private var listener: WinHostConnection.Listener?
    /// Połączenia przed `hello` (nikt inny ich jeszcze nie trzyma); pod `pendingLock`.
    private var pending: [ObjectIdentifier: WinHostConnection] = [:]
    private let pendingLock = NSLock()
    private let token = (0..<16).map { _ in UInt8.random(in: 0...255) }
    private var screen = CGRect.zero
    private var lastList: WinWindowList?
    private var foregroundKey: String?
    private var timer: Timer?
    private var stopped = false

    /// Windows przysyła numery aplikacji (i rozumie WINVIEW_ACTIVATE / WINVIEW_CLOSE).
    private(set) var windowsKnowsApps = false

    init() {}

    func stop() {
        stopped = true
        timer?.invalidate()
        timer = nil
        for host in hosts.values {
            host.connection?.send(.quit)
            host.connection?.close()
            if host.connection == nil { host.process?.terminate() }
        }
        hosts = [:]
        listener?.stop()
        listener = nil
    }

    func setApp(_ info: WinAppInfo) {
        apps[info.id] = info
        if let list = lastList { update(list, screen: screen) }
    }

    private func key(of window: WinWindowDescriptor) -> String? {
        guard let app = window.app, let info = apps[app] else { return nil }
        return WinAppBundles.sanitizedKey(info.key)
    }

    // MARK: - Lista okien

    /// Nowa lista z Windowsa. Wywoływać przed pokazaniem okien w Seam (`localWindows`).
    func update(_ list: WinWindowList, screen: CGRect) {
        guard !stopped else { return }
        self.screen = screen
        lastList = list
        if list.hasApps { windowsKnowsApps = true }
        var byKey: [String: [WinWindowDescriptor]] = [:]
        var order: [String] = []
        for window in list.windows {
            guard let key = key(of: window) else { continue }
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append(window)
        }
        let now = Date()
        var routesChanged = false
        for (key, host) in hosts {
            let windows = byKey[key] ?? []
            let ids = windows.map(\.id)
            if ids != host.windowIDs {
                host.windowIDs = ids
                routesChanged = true
                // Okna, których już nie ma, nie są pokazywane przez pomocnika.
                let before = host.visible.count
                host.visible = host.visible.filter { ids.contains($0.key) }
                if host.visible.count != before { routesChanged = true }
            }
            if windows.isEmpty {
                if host.emptySince == nil { host.emptySince = now }
            } else {
                host.emptySince = nil
            }
            sendLayout(host, windows: windows, list: list)
        }
        // Nowa aplikacja z oknem (same menu/podpowiedzi nie dostają ikony w Docku).
        if WinAppBundles.isAvailable, windowsKnowsApps {
            for key in order where hosts[key] == nil {
                guard let windows = byKey[key], windows.contains(where: { !$0.isPopup }),
                      let app = windows.first?.app, let info = apps[app] else { continue }
                if let until = retryAfter[key], until > now { continue }
                if let until = closingUntil[key], until > now { continue }
                launch(key: key, info: info, windows: windows.map(\.id))
                routesChanged = true
            }
        }
        // Okno aktywne na Windowsie: jeśli na Macu pracuje się teraz w oknach Windows, aktywna staje się jego aplikacja.
        let foreground = list.windows.first(where: \.isForeground)
        let newKey = foreground.flatMap { key(of: $0) }
        if let foreground, newKey != foregroundKey {
            foregroundKey = newKey
            if workingInWindowsApps {
                if let newKey, let host = hosts[newKey], host.visible[foreground.id] != nil {
                    activate(host)
                } else if NSWorkspace.shared.frontmostApplication?.processIdentifier != getpid() {
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        } else if foreground == nil {
            foregroundKey = nil
        }
        scheduleTimer()
        if routesChanged { onRoutesChanged?() }
    }

    /// Okna pokazywane przez pomocników – Seam ich nie pokazuje i nie dekoduje.
    var hostedVisible: Set<UInt32> {
        var ids = Set<UInt32>()
        for host in hosts.values { ids.formUnion(host.visible.keys) }
        return ids
    }

    /// Numer okna pomocnika pokazującego dane okno Windows i pid pomocnika (samotest).
    func hostedWindow(_ id: UInt32) -> (number: Int, pid: pid_t)? {
        for host in hosts.values {
            if let number = host.visible[id] { return (number, host.process?.processIdentifier ?? 0) }
        }
        return nil
    }

    /// Numery okien macOS pomocników (do sprawdzania, czy okno Windows nie jest zasłonięte).
    var hostedNumbers: Set<Int> {
        var numbers = Set<Int>()
        for host in hosts.values { numbers.formUnion(host.visible.values) }
        return numbers
    }

    /// Strumienie okien do przekazania pomocnikom (gotowym).
    var routes: [UInt32: WinHostConnection] {
        var routes: [UInt32: WinHostConnection] = [:]
        for host in hosts.values {
            guard let connection = host.connection else { continue }
            for id in host.windowIDs { routes[id] = connection }
        }
        return routes
    }

    private func sendLayout(_ host: Host, windows: [WinWindowDescriptor], list: WinWindowList) {
        guard let connection = host.connection else { return }
        var w = ByteWriter()
        for value in [screen.minX, screen.minY, screen.width, screen.height] { w.u64(Double(value).bitPattern) }
        w.raw(WinWindowList(displayWidth: list.displayWidth, displayHeight: list.displayHeight, windows: windows).payload)
        guard w.bytes != host.lastLayout else { return }
        host.lastLayout = w.bytes
        connection.send(.layout, w.bytes)
    }

    // MARK: - Aktywacja

    /// Aktywna aplikacja Maca to Seam albo któryś pomocnik – użytkownik pracuje w oknach Windows.
    private var workingInWindowsApps: Bool {
        guard let front = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return false }
        return front == getpid() || hosts.values.contains { $0.process?.processIdentifier == front }
    }

    /// Kursor wjechał na okno Windows: aktywna staje się aplikacja okna aktywnego na Windowsie.
    /// false = to okno pokazuje Seam (aktywować trzeba Seam).
    func activateForeground() -> Bool {
        guard let list = lastList else { return false }
        let window = list.windows.first(where: \.isForeground) ?? list.windows.first(where: { !$0.isPopup })
        guard let window, let key = key(of: window), let host = hosts[key], host.visible[window.id] != nil else { return false }
        activate(host)
        return true
    }

    private func activate(_ host: Host) {
        host.activatedBySeamAt = Date()
        host.connection?.send(.activate)
        // Spółdzielcza aktywacja (macOS 14+): aktywna aplikacja oddaje pierwszeństwo pomocnikowi.
        if let process = host.process {
            if #available(macOS 14.0, *) { NSApp.yieldActivation(to: process) }
            process.activate()
        }
    }

    /// Kształt kursora dla aktywnego pomocnika. false = aktywny jest Seam albo inna aplikacja.
    func setCursor(_ shape: UInt8) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication?.processIdentifier, front != getpid(),
              let host = hosts.values.first(where: { $0.process?.processIdentifier == front }) else { return false }
        host.connection?.send(.cursor, [shape], droppable: true)
        return true
    }

    // MARK: - Pomocnicy

    private func launch(key: String, info: WinAppInfo, windows: [UInt32]) {
        let host = Host(key: key, info: info)
        host.windowIDs = windows
        hosts[key] = host
        guard ensureListener() else {
            fail(host)
            return
        }
        let path = listener!.path
        let token = self.token.map { String(format: "%02x", $0) }.joined()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let bundle = try? WinAppBundles.prepare(info)
            DispatchQueue.main.async {
                guard let self, self.hosts[key] === host else { return }
                guard let bundle else {
                    self.fail(host)
                    return
                }
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                configuration.addsToRecentItems = false
                configuration.createsNewApplicationInstance = true
                configuration.promptsUserIfNeeded = false
                configuration.arguments = ["--seam-socket", path, "--seam-token", token, "--seam-key", key]
                NSWorkspace.shared.openApplication(at: bundle, configuration: configuration) { app, _ in
                    DispatchQueue.main.async {
                        guard self.hosts[key] === host else {
                            app?.terminate()
                            return
                        }
                        guard let app else {
                            self.fail(host)
                            return
                        }
                        host.process = app
                    }
                }
            }
        }
    }

    private func fail(_ host: Host) {
        guard hosts[host.key] === host else { return }
        hosts[host.key] = nil
        host.connection?.close()
        host.process?.terminate()
        retryAfter[host.key] = Date().addingTimeInterval(60)
        onRoutesChanged?()
    }

    private func ensureListener() -> Bool {
        if listener != nil { return true }
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("seam-hosts-\(getpid())-\(UInt32.random(in: 0...UInt32.max)).sock")
        listener = WinHostConnection.Listener(path: path, queue: DispatchQueue(label: "seam.hosts.accept")) { [weak self] connection in
            self?.accepted(connection)
        }
        return listener != nil
    }

    /// Kolejka gniazda: pierwsza wiadomość to `hello` z tokenem.
    private func accepted(_ connection: WinHostConnection) {
        let token = self.token
        let id = ObjectIdentifier(connection)
        pendingLock.withLock { pending[id] = connection }
        var greeted = false
        connection.onMessage = { [weak self, weak connection] type, payload in
            guard let connection else { return }
            if !greeted {
                var r = ByteReader(payload)
                guard type == .hello, let received = r.bytes(16), received == token, let rawPid = r.u32() else {
                    connection.close()
                    return
                }
                greeted = true
                self?.pendingLock.withLock { _ = self?.pending.removeValue(forKey: id) }
                let key = r.restAsString()
                DispatchQueue.main.async { self?.greeted(connection, appKey: key, pid: pid_t(bitPattern: rawPid)) }
                return
            }
            DispatchQueue.main.async { self?.received(type, payload, from: connection) }
        }
        connection.onClosed = { [weak self, weak connection] in
            self?.pendingLock.withLock { _ = self?.pending.removeValue(forKey: id) }
            DispatchQueue.main.async {
                guard let self, let connection else { return }
                self.disconnected(connection)
            }
        }
        connection.start()
    }

    private func greeted(_ connection: WinHostConnection, appKey: String, pid: pid_t) {
        guard !stopped, let host = hosts[appKey], host.connection == nil else {
            connection.send(.quit)
            connection.close()
            return
        }
        host.connection = connection
        if host.process == nil { host.process = NSRunningApplication(processIdentifier: pid) }
        if let list = lastList {
            let windows = list.windows.filter { key(of: $0) == host.key }
            sendLayout(host, windows: windows, list: list)
        }
        // Dekoder pomocnika zaczyna od klatki kluczowej.
        onKeyframeNeeded?()
        onRoutesChanged?()
    }

    private func received(_ type: WinHostMessage, _ payload: [UInt8], from connection: WinHostConnection) {
        guard let host = hosts.values.first(where: { $0.connection === connection }) else { return }
        var r = ByteReader(payload)
        switch type {
        case .numbers:
            guard let count = r.u8() else { return }
            var visible: [UInt32: Int] = [:]
            for _ in 0..<count {
                guard let id = r.u32(), let number = r.u32() else { return }
                if host.windowIDs.contains(id) { visible[id] = Int(number) }
            }
            guard visible != host.visible else { return }
            let foreground = lastList?.windows.first(where: \.isForeground)?.id
            let tookForeground = foreground.map { visible[$0] != nil && host.visible[$0] == nil } ?? false
            host.visible = visible
            onRoutesChanged?()
            // Okno aktywne na Windowsie przeszło do pomocnika – to on jest teraz aktywną aplikacją.
            if tookForeground, workingInWindowsApps { activate(host) }
        case .keyframe:
            onKeyframeNeeded?()
        case .activated:
            guard windowsKnowsApps, Date().timeIntervalSince(host.activatedBySeamAt) > 1 else { return }
            let requested = r.u32() ?? 0
            let id = requested != 0 && host.windowIDs.contains(requested) ? requested : host.windowIDs.first { id in
                lastList?.windows.first(where: { $0.id == id })?.isPopup == false
            }
            if let id { onActivateWindow?(id) }
        case .closeRequested:
            guard windowsKnowsApps else { return }
            let ids = host.windowIDs.filter { id in lastList?.windows.first(where: { $0.id == id })?.isPopup == false }
            closingUntil[host.key] = Date().addingTimeInterval(3)
            onCloseWindows?(ids)
        default:
            break
        }
    }

    private func disconnected(_ connection: WinHostConnection) {
        guard let host = hosts.values.first(where: { $0.connection === connection }) else { return }
        hosts[host.key] = nil
        // Pomocnik zakończony bez prośby – okna wracają do Seam, nowy pomocnik po chwili.
        if closingUntil[host.key] == nil { retryAfter[host.key] = Date().addingTimeInterval(2) }
        onRoutesChanged?()
        scheduleTimer()
    }

    /// Porządki: pomocnicy bez okien kończą pracę, nieuruchomieni po czasie przechodzą w tryb zapasowy.
    private func scheduleTimer() {
        guard timer == nil, !hosts.isEmpty || !retryAfter.isEmpty || !closingUntil.isEmpty else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 0.2
    }

    private func tick() {
        let now = Date()
        for host in hosts.values {
            if let empty = host.emptySince, now.timeIntervalSince(empty) > 1.5 {
                hosts[host.key] = nil
                if let connection = host.connection {
                    connection.send(.quit)
                    connection.close()
                } else {
                    host.process?.terminate()
                }
                onRoutesChanged?()
            } else if host.connection == nil, now.timeIntervalSince(host.launchedAt) > 10 {
                fail(host)
            }
        }
        let reopen = closingUntil.contains { $0.value <= now } || retryAfter.contains { $0.value <= now }
        retryAfter = retryAfter.filter { $0.value > now }
        closingUntil = closingUntil.filter { $0.value > now }
        if reopen, let list = lastList { update(list, screen: screen) }
        if hosts.isEmpty, retryAfter.isEmpty, closingUntil.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }
}
