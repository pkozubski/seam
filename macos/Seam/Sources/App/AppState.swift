import AppKit
import Combine
import Foundation
import OSLog
import SwiftUI

struct LogEntry: Identifiable {
    let id = UUID()
    let time: Date
    let text: String
}

/// Stan aplikacji dla widoków. `@Observable` śledzi każdą właściwość osobno: widok odświeża się
/// tylko po zmianie tego, co sam czyta, a nie przy każdej zmianie stanu (to dawało ciągłe
/// przerysowywanie okna i ikony w pasku menu).
@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    var settings: Settings {
        didSet {
            guard settings != oldValue, !isPreview else { return }
            if settings.launchAtLogin != oldValue.launchAtLogin {
                applyLaunchAtLogin(settings.launchAtLogin)
            }
            settings.save()
            engine.update(config: settings.engineConfig)
        }
    }

    private(set) var isListening = false
    private(set) var listenError: String?
    private(set) var peer: ControlServer.PeerInfo?
    private(set) var cursorOnMac = false
    private(set) var audioStreaming = false
    private(set) var audioDescription = ""
    private(set) var audioError: String?
    private(set) var audioPackets: UInt64 = 0
    private(set) var audioSendErrors: UInt64 = 0
    private(set) var audioPermission: SystemAudioTap.Permission = .unknown
    private(set) var accessibilityGranted = false
    private(set) var screenCaptureGranted = false
    private(set) var displayStreaming = false
    private(set) var displayEdge: ScreenEdge?
    private(set) var displayDescription = ""
    private(set) var displayError: String?
    private(set) var displayStats: DisplayStreamer.Stats?
    private(set) var clipboardStatus = L10n.text("Brak synchronizacji w tej sesji", "No synchronization in this session")
    private(set) var loginItemStatus = LoginItem.statusDescription
    var loginItemError: String?
    private(set) var pairingCode = PairingKeyStore.shared.displayCode
    private(set) var pairingStorageError = PairingKeyStore.shared.storageError
    private(set) var log: [LogEntry] = []

    @ObservationIgnored let engine: Engine
    @ObservationIgnored let updater = Updater()
    @ObservationIgnored private var permissionTimer: Timer?
    @ObservationIgnored private var activityObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var audioPermissionInFlight = false
    @ObservationIgnored private var audioPermissionCheckedAt: Date?
    @ObservationIgnored private var updateTimer: Timer?
    @ObservationIgnored private var updaterSink: AnyCancellable?
    @ObservationIgnored private let logger = Logger(subsystem: "com.borderlessmouse.mac", category: "app")
    /// Poziom w podglądzie UI (bez silnika audio).
    @ObservationIgnored private var demoAudioLevel: Float?

    /// Poziom dźwięku 0–1. Nie jest obserwowany: miernik odczytuje go sam, tylko gdy jest widoczny,
    /// więc strumień audio nie budzi wątku głównego kilkadziesiąt razy na sekundę.
    var audioLevel: Float { demoAudioLevel ?? engine.audioLevel }

    /// Stan bez sieci i uprawnień, wypełniony przykładowymi danymi – tylko dla
    /// podglądu interfejsu (`--ui-preview`).
    static func demo() -> AppState {
        let state = AppState(preview: true)
        state.fillWithDemoData()
        return state
    }

    @ObservationIgnored private let isPreview: Bool

    private init(preview: Bool = false) {
        isPreview = preview
        var s = preview ? Settings() : Settings.load()
        // stan autostartu bierzemy z systemu – to on jest źródłem prawdy
        if !preview { LoginItem.refreshIfNeeded(wasEnabled: s.launchAtLogin) }
        s.launchAtLogin = LoginItem.isEnabled
        // Jedno przypisanie: przy @Observable każde kolejne w init wywołałoby już didSet (zapis i autostart).
        settings = s
        engine = Engine(config: s.engineConfig)
        engine.onEvent = { [weak self] event in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.apply(event) } }
        }
        accessibilityGranted = InputInjector.isAccessibilityTrusted
        screenCaptureGranted = DisplayCapture.hasPermission
        guard !preview else { return }
        appendLog(L10n.text("Wersja \(Updater.versionDescription)", "Version \(Updater.versionDescription)"))
        engine.setAccessibilityGranted(accessibilityGranted)
        engine.start()
        watchPermissions()
        if let finished = Updater.consumeRelaunchMarker() {
            updater.celebrate(version: finished.version, notes: finished.notes)
            SettingsNavigation.shared.present(.updates)
        }
        scheduleUpdateChecks()
        updaterSink = updater.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .available(let r): self?.appendLog(L10n.text("Dostępna aktualizacja \(r.version) (\(r.tag))", "Update \(r.version) is available (\(r.tag))"))
                case .upToDate: self?.appendLog(L10n.text("Aktualizacje: masz najnowszą wersję \(Updater.currentVersion)", "Updates: version \(Updater.currentVersion) is current"))
                case .failed(let msg): self?.appendLog(L10n.text("Aktualizacje: \(msg)", "Updates: \(msg)"))
                case .installing: self?.appendLog(L10n.text("Aktualizacja pobrana, podmiana i restart…", "Update downloaded; replacing and restarting…"))
                case .updated(let version): self?.appendLog(L10n.text("Zaktualizowano do \(version)", "Updated to \(version)"))
                default: break
                }
            }
    }

    private func scheduleUpdateChecks() {
        // Test builds check frequently and install only when the session can restart.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            await self?.checkAutomaticUpdates()
        }
        let interval = UpdatePolicy.checkInterval(isDev: Updater.isDevChannel)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkAutomaticUpdates()
            }
        }
        // Luz pozwala systemowi zgrać wybudzenie z innymi i nie budzić procesora tylko dla nas.
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
    }

    /// Zgody sprawdzamy często tylko wtedy, gdy użytkownik jest w aplikacji (wraca z Ustawień
    /// systemowych); w tle wystarczy rzadko, żeby wyłapać cofnięcie zgody.
    private func watchPermissions() {
        let center = NotificationCenter.default
        activityObservers = [
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshPermissions()
                    self?.schedulePermissionTimer(active: true)
                }
            },
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedulePermissionTimer(active: false) }
            },
        ]
        schedulePermissionTimer(active: NSApplication.shared.isActive)
    }

    private func schedulePermissionTimer(active: Bool) {
        permissionTimer?.invalidate()
        let interval: TimeInterval = active ? 2 : 30
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
        timer.tolerance = interval * 0.25
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    private func checkAutomaticUpdates() async {
        guard settings.autoCheckUpdates else { return }
        await updater.check(silent: true)
        guard case .available = updater.state, await mayAutoRestart() else { return }
        await updater.install(codesignIdentity: settings.codesignIdentity, mayRestart: { [weak self] in
            await self?.mayAutoRestart() ?? false
        })
    }

    private func mayAutoRestart() async -> Bool {
        guard let anyInput = CGEventType(rawValue: UInt32.max) else { return false }
        let sessionAllowsRestart = await engine.canRestartForUpdate()
        return UpdatePolicy.canAutoInstall(isDev: Updater.isDevChannel, enabled: settings.autoCheckUpdates,
            idleSeconds: CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput),
            sessionAllowsRestart: sessionAllowsRestart && !cursorOnMac)
    }

    private func fillWithDemoData() {
        settings.hasCompletedOnboarding = true
        settings.deviceName = "MacBook Pro"
        pairingCode = "DEMO1-DEMO2-DEMO3-DEMO4-DEMO5-0"
        pairingStorageError = nil
        isListening = true
        peer = ControlServer.PeerInfo(name: L10n.text("PC-BIURO", "PC-DESK"), address: "192.168.1.42")
        cursorOnMac = true
        accessibilityGranted = true
        audioStreaming = true
        audioPermission = .granted
        audioDescription = "48000 Hz · stereo · 16-bit → 192.168.1.42:47802"
        demoAudioLevel = 0.42
        audioPackets = 18_432
        screenCaptureGranted = true
        displayStreaming = true
        displayEdge = .right
        displayDescription = "2560×1440 · H.264 22 Mb/s"
        displayStats = DisplayStreamer.Stats(framesPerSecond: 58, kilobitsPerSecond: 6_420, dropped: 0, width: 2560, height: 1440)
        clipboardStatus = L10n.text("Wysłano 128 zn. do Windowsa · 21:40:12", "Sent 128 characters to Windows · 21:40:12")
        loginItemStatus = LoginItem.statusDescription
        log = [
            LogEntry(time: Date().addingTimeInterval(-95), text: L10n.text("Nasłuchiwanie TCP na porcie 47800", "Listening on TCP port 47800")),
            LogEntry(time: Date().addingTimeInterval(-80), text: L10n.text("Discovery UDP nasłuchuje na porcie 47801", "Discovery is listening on UDP port 47801")),
            LogEntry(time: Date().addingTimeInterval(-42), text: L10n.text("Połączono: PC-BIURO (192.168.1.42)", "Connected: PC-DESK (192.168.1.42)")),
            LogEntry(time: Date().addingTimeInterval(-20), text: L10n.text("Audio: 48000 Hz · stereo · 16-bit, bufor 256 ramek", "Audio: 48000 Hz · stereo · 16-bit, 256-frame buffer")),
            LogEntry(time: Date().addingTimeInterval(-4), text: L10n.text("Kursor przeszedł na Maca", "Pointer moved to Mac")),
        ]
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--ui-display-edge"), index + 1 < args.count {
            displayEdge = ["left": ScreenEdge.left, "right": .right, "top": .top, "bottom": .bottom][args[index + 1]] ?? .right
        }
        if args.contains("--ui-display-off") {
            settings.displayEnabled = false
            displayStreaming = false
            displayEdge = nil
        }
        if args.contains("--ui-disconnected") {
            peer = nil
            cursorOnMac = false
            audioStreaming = false
            displayStreaming = false
            displayEdge = nil
            log = []
        }
        if args.contains("--ui-missing-permissions") {
            accessibilityGranted = false
            screenCaptureGranted = false
            displayStreaming = false
            displayEdge = nil
            audioPermission = .unknown
        }
        if args.contains("--ui-onboarding") {
            settings.hasCompletedOnboarding = false
        }
    }

    func clearLog() { log.removeAll() }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        guard !isPreview else { return }
        do {
            let mechanism = try LoginItem.setEnabled(enabled)
            loginItemError = nil
            appendLog(enabled
                      ? L10n.text("Autostart włączony (\(mechanism == .service ? "element logowania" : "LaunchAgent"))",
                                  "Launch at login enabled (\(mechanism == .service ? "login item" : "LaunchAgent"))")
                      : L10n.text("Autostart wyłączony", "Launch at login disabled"))
        } catch {
            loginItemError = error.localizedDescription
            appendLog("Autostart: \(error.localizedDescription)")
        }
        loginItemStatus = LoginItem.statusDescription
    }

    func checkForUpdates() {
        Task { @MainActor in await updater.check(silent: false) }
    }

    func installUpdate() {
        Task { @MainActor in await updater.install(codesignIdentity: settings.codesignIdentity, announce: true) }
    }

    var statusSummary: (text: String, color: Color) {
        if !isListening { return (L10n.text("Nie nasłuchuje", "Unavailable"), .red) }
        if let peer {
            if cursorOnMac { return (L10n.text("Sterowanie z \(peer.name)", "Controlled by \(peer.name)"), .green) }
            return (L10n.text("Połączono z \(peer.name)", "Connected to \(peer.name)"), .green) }
        return (L10n.text("Czeka na Windows", "Waiting for Windows"), .orange)
    }

    // MARK: - Akcje

    func refreshPermissions() {
        let screen = DisplayCapture.hasPermission
        if screen != screenCaptureGranted {
            screenCaptureGranted = screen
            appendLog(screen
                      ? L10n.text("Zgoda na nagrywanie ekranu nadana", "Screen Recording permission granted")
                      : L10n.text("Brak zgody na nagrywanie ekranu", "Screen Recording permission missing"))
        }
        let granted = InputInjector.isAccessibilityTrusted
        if granted != accessibilityGranted {
            accessibilityGranted = granted
            engine.setAccessibilityGranted(granted)
            appendLog(granted
                      ? L10n.text("Uprawnienie Dostępność nadane", "Accessibility permission granted")
                      : L10n.text("Brak uprawnienia Dostępność", "Accessibility permission missing"))
        }
    }

    func requestAccessibility() {
        InputInjector.requestAccessibility()
        refreshPermissions()
    }

    func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openAudioCaptureSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")
    }

    func requestScreenCapture() {
        // macOS pyta tylko raz; przy odmowie od razu otwieramy właściwy panel.
        if !DisplayCapture.requestPermission() { openScreenCaptureSettings() }
        refreshPermissions()
    }

    func openScreenCaptureSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    var displayStatusText: String {
        if displayStreaming {
            var text = L10n.text("Działa: \(displayDescription)", "Running: \(displayDescription)")
            if let stats = displayStats {
                text += L10n.text(" · \(stats.framesPerSecond) kl./s · \(stats.kilobitsPerSecond / 1000) Mb/s",
                                  " · \(stats.framesPerSecond) fps · \(stats.kilobitsPerSecond / 1000) Mb/s")
            }
            return text
        }
        if let displayError { return displayError }
        if !VirtualDisplay.isSupported {
            return L10n.text("Ta wersja macOS nie udostępnia wirtualnych monitorów.",
                             "This macOS version does not provide virtual displays.")
        }
        return L10n.text("Nieaktywny – Windows tworzy go po połączeniu, jeśli ma włączony ekran Maca.",
                         "Inactive — Windows starts it after connecting when the Mac display is enabled there.")
    }

    func stopDisplay() { engine.stopDisplay() }

    // MARK: - Zgoda na dźwięk systemowy

    /// `nil` = jeszcze nie wiadomo (nie sprawdzaliśmy albo trwa sprawdzanie).
    var audioPermissionGranted: Bool? {
        switch audioPermission {
        case .granted: return true
        case .denied, .failed: return false
        case .unknown, .checking: return nil
        }
    }

    var audioPermissionSubtitle: String {
        switch audioPermission {
        case .granted:
            return L10n.text("Nadane – Mac może wysyłać dźwięk systemowy.",
                             "Granted — the Mac can stream system audio.")
        case .checking:
            return L10n.text("Sprawdzanie… jeśli macOS zapyta, potwierdź zgodę.",
                             "Checking… confirm the macOS prompt if it appears.")
        case .unknown:
            return L10n.text("Kliknij „Poproś”, żeby sprawdzić zgodę i w razie potrzeby wywołać pytanie macOS.",
                             "Press “Request” to check the permission and trigger the macOS prompt if needed.")
        case let .denied(message):
            return L10n.text("Brak zgody: \(message) Jeśli w Ustawieniach systemowych przełącznik jest włączony, użyj „Napraw zgodę” – po zmianie podpisu aplikacji macOS trzyma stary wpis.",
                             "Not granted: \(message) If the switch is already on in System Settings, use “Repair” — macOS keeps a stale entry after the app signature changes.")
        case let .failed(message):
            return L10n.text("Nie udało się sprawdzić: \(message)", "Could not verify: \(message)")
        }
    }

    /// Jedyny sposób na sprawdzenie tej zgody to spróbować założyć tap – przy
    /// braku wpisu w TCC macOS pokaże wtedy pytanie.
    func checkAudioPermission(force: Bool) {
        guard !isPreview else { return }
        if audioStreaming {
            applyAudioPermission(.granted)
            return
        }
        guard !audioPermissionInFlight else { return }
        if !force {
            // automatyczny test może wywołać systemowe pytanie – nigdy w tle
            // (np. przy starcie z logowania z ukrytym oknem)
            guard settings.audioEnabled, NSApp.isActive else { return }
            if audioPermission.isGranted, let last = audioPermissionCheckedAt,
               Date().timeIntervalSince(last) < 30 { return }
        }
        audioPermissionInFlight = true
        audioPermission = .checking
        engine.probeAudioPermission { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.audioPermissionInFlight = false
                self.audioPermissionCheckedAt = Date()
                self.applyAudioPermission(result)
            }
        }
    }

    /// Kasuje wpis TCC dla tej aplikacji i od razu prosi o zgodę na nowo.
    /// Potrzebne, gdy Ustawienia systemowe pokazują zgodę, a macOS jej nie
    /// honoruje (wpis pamięta poprzedni podpis aplikacji).
    func repairAudioPermission() {
        guard !isPreview, !audioPermissionInFlight else { return }
        let bundleID = Bundle.main.bundleIdentifier ?? "com.borderlessmouse.mac"
        appendLog(L10n.text("Kasowanie wpisu zgody na dźwięk (tccutil reset AudioCapture \(bundleID))",
                            "Resetting the audio permission entry (tccutil reset AudioCapture \(bundleID))"))
        audioPermissionInFlight = true
        audioPermission = .checking
        DispatchQueue.global(qos: .userInitiated).async {
            let message = Self.runTccutilReset(bundleID: bundleID)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.audioPermissionInFlight = false
                if let message { self.appendLog(message) }
                self.audioPermission = .unknown
                self.checkAudioPermission(force: true)
            }
        }
    }

    /// Zwraca komunikat do dziennika, gdy reset się nie powiódł.
    private nonisolated static func runTccutilReset(bundleID: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "AudioCapture", bundleID]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard task.terminationStatus != 0 else { return nil }
            let text = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return L10n.text("tccutil zakończył się kodem \(task.terminationStatus): \(text)",
                             "tccutil exited with code \(task.terminationStatus): \(text)")
        } catch {
            return L10n.text("Nie udało się uruchomić tccutil: \(error.localizedDescription)",
                             "Could not run tccutil: \(error.localizedDescription)")
        }
    }

    private func applyAudioPermission(_ value: SystemAudioTap.Permission) {
        guard audioPermission != value else { return }
        let wasGranted = audioPermission.isGranted
        audioPermission = value
        switch value {
        case .granted where !wasGranted:
            appendLog(L10n.text("Zgoda na nagrywanie dźwięku systemowego nadana",
                                "System audio recording permission granted"))
        case let .denied(message):
            appendLog(L10n.text("Brak zgody na nagrywanie dźwięku systemowego: \(message)",
                                "System audio recording permission missing: \(message)"))
        case let .failed(message):
            appendLog(L10n.text("Test dźwięku nie powiódł się: \(message)",
                                "Audio permission test failed: \(message)"))
        default:
            break
        }
    }

    func disconnectPeer() { engine.disconnectPeer() }
    func stopAudio() { engine.stopAudio() }
    func restartServer() { engine.restartServer() }

    func copyPairingCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pairingCode, forType: .string)
        appendLog(L10n.text("Skopiowano kod parowania", "Pairing code copied"))
    }

    func regeneratePairingCode() {
        let store = PairingKeyStore.shared
        if let error = store.regenerate() {
            pairingStorageError = error
            appendLog("Kod parowania: \(error)")
            return
        }
        pairingCode = store.displayCode
        pairingStorageError = nil
        engine.update(config: settings.engineConfig)
        appendLog(L10n.text("Wygenerowano nowy kod parowania; poprzednie połączenia zostały unieważnione",
                            "Generated a new pairing code; previous connections were revoked"))
    }

    func completeOnboarding() {
        settings.hasCompletedOnboarding = true
    }

    func shutdown() {
        permissionTimer?.invalidate()
        updateTimer?.invalidate()
        activityObservers.forEach(NotificationCenter.default.removeObserver)
        activityObservers = []
        engine.stop()
    }

    private func open(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }

    // MARK: - Zdarzenia z silnika

    private func apply(_ event: Engine.Event) {
        switch event {
        case let .listening(ok, error):
            isListening = ok
            listenError = error
        case let .peerConnected(info):
            peer = info
        case .peerDisconnected:
            peer = nil
            displayEdge = nil
            cursorOnMac = false
            displayStreaming = false
            displayStats = nil
        case let .cursorOnMac(active):
            cursorOnMac = active
        case let .audioStarted(desc):
            audioStreaming = true
            audioDescription = desc
            audioError = nil
            audioPackets = 0
            audioSendErrors = 0
        case .audioStopped:
            audioStreaming = false
            audioDescription = ""
        case let .audioError(message):
            audioStreaming = false
            audioError = message
        case let .audioPermission(value):
            audioPermissionCheckedAt = Date()
            applyAudioPermission(value)
        case let .audioStats(packets, errors):
            // Przy @Observable każde przypisanie powiadamia widoki, także tą samą wartością.
            if audioPackets != packets { audioPackets = packets }
            if audioSendErrors != errors { audioSendErrors = errors }
        case let .clipboardSent(summary):
            clipboardStatus = L10n.text("Wysłano \(summary) do Windowsa · \(Self.timeFormatter.string(from: Date()))",
                                        "Sent \(summary) to Windows · \(Self.timeFormatter.string(from: Date()))")
        case let .clipboardReceived(summary):
            clipboardStatus = L10n.text("Odebrano \(summary) z Windowsa · \(Self.timeFormatter.string(from: Date()))",
                                        "Received \(summary) from Windows · \(Self.timeFormatter.string(from: Date()))")
        case let .clipboardError(message):
            clipboardStatus = message
        case let .displayStarted(desc, edge):
            displayStreaming = true
            displayEdge = edge
            displayDescription = desc
            displayError = nil
            displayStats = nil
        case .displayStopped:
            displayStreaming = false
            displayEdge = nil
            displayDescription = ""
            displayStats = nil
        case let .displayError(message):
            displayStreaming = false
            displayEdge = nil
            displayError = message
            displayStats = nil
        case let .displayStats(stats):
            if displayStats != stats { displayStats = stats }
        case let .log(text):
            appendLog(text)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private func appendLog(_ text: String) {
        logger.notice("\(text, privacy: .public)")
        log.append(LogEntry(time: Date(), text: text))
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }
}
