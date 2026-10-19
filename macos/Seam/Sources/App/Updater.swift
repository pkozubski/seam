import AppKit
import CryptoKit
import Foundation

/// Auto-updater oparty o GitHub Releases: sprawdza najnowszy tag, pobiera
/// `Seam-macOS.zip`, weryfikuje SHA-256, projektowy podpis ECDSA
/// i stały certyfikat wydawcy, a następnie atomowo podmienia bundle.
@MainActor
final class Updater: ObservableObject {
    static let owner = "pkozubski"
    static let repo = "seam"
    static let assetName = "Seam-macOS.zip"
    static let checksumsName = "SHA256SUMS.txt"
    static let signatureName = "Seam-macOS.zip.sig"
    private static let maximumDownloadBytes = 300 * 1024 * 1024

    struct Release: Equatable {
        let version: String
        let tag: String
        let notes: String
        let pageURL: URL
        let assetURL: URL
        let checksumsURL: URL?
        let signatureURL: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate(String)
        case available(Release)
        case downloading
        case verifying
        case installing
        /// This launch finished an update the user started; holds the new version.
        case updated(String)
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .downloading, .verifying, .installing: return true
            default: return false
            }
        }
    }

    @Published private(set) var state: State = .idle
    /// Release notes of the version this launch just updated to.
    @Published private(set) var installedNotes: String?
    /// Fast-changing install progress, kept apart so only the bar redraws on every report.
    let progress = UpdateProgress()

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static var isDevChannel: Bool {
        Bundle.main.infoDictionary?["UpdateChannel"] as? String == "dev"
    }

    static var versionDescription: String {
        currentVersion + (isDevChannel ? L10n.text(" (kanał testowy)", " (test channel)") : "")
    }

    static var automaticUpdatesDescription: String {
        isDevChannel
            ? L10n.text("Co 2 minuty; instalacja po minucie bezczynności, bez zdalnego sterowania i przeniesionych okien.",
                        "Every 2 minutes; installs after a minute of inactivity, with no remote control or transferred windows.")
            : L10n.text("Po starcie i co 6 godzin, przez GitHub Releases.", "At startup and every 6 hours, through GitHub Releases.")
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    // MARK: - Sprawdzanie

    func check(silent: Bool) async {
        if case .checking = state { return }
        if state.isBusy { return }
        let previous = state
        state = .checking
        // Background checks keep the "updated" confirmation until something newer appears.
        var quiet = State.idle
        if case .updated = previous { quiet = previous }
        do {
            guard let release = try await fetchLatest() else {
                state = silent ? quiet : .failed(L10n.text("Brak wydań na GitHubie", "No releases found on GitHub"))
                return
            }
            if Self.isNewer(release.version, than: Self.currentVersion) {
                state = .available(release)
            } else if case .updated = previous {
                state = previous
            } else {
                state = .upToDate(Self.timeFormatter.string(from: Date()))
            }
        } catch {
            state = silent ? quiet : .failed(error.localizedDescription)
        }
    }

    private func fetchLatest() async throws -> Release? {
        let path = UpdatePolicy.releasePath(isDev: Self.isDevChannel)
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.owner)/\(Self.repo)/\(path)")!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Seam-macOS/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw UpdaterError.http(http.statusCode) }
        return try Self.parseRelease(data, isDev: Self.isDevChannel)
    }

    static func parseRelease(_ data: Data, isDev: Bool) throws -> Release? {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
              let assets = json["assets"] as? [[String: Any]] else { throw UpdaterError.malformed }
        var assetURL: URL?
        var checksumsURL: URL?
        var signatureURL: URL?
        for asset in assets {
            guard let name = asset["name"] as? String,
                  let url = (asset["browser_download_url"] as? String).flatMap(URL.init(string:)) else { continue }
            if name == Self.assetName { assetURL = url }
            if name == Self.checksumsName { checksumsURL = url }
            if name == Self.signatureName { signatureURL = url }
        }
        guard let assetURL else { return nil }
        guard checksumsURL != nil else { throw UpdaterError.missingChecksum }
        guard let signatureURL else { throw UpdaterError.missingSignature }
        guard let version = UpdatePolicy.releaseVersion(tag: tag, title: json["name"] as? String ?? "", isDev: isDev) else {
            throw UpdaterError.malformed
        }
        return Release(version: version, tag: tag, notes: (json["body"] as? String) ?? "",
                       pageURL: page, assetURL: assetURL, checksumsURL: checksumsURL,
                       signatureURL: signatureURL)
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.split(whereSeparator: { $0 == "." || $0 == "-" }).prefix(3).map { Int($0) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Instalacja

    /// `announce` leaves a marker so the relaunched app finishes the bar and shows what changed;
    /// silent background installs skip it.
    func install(codesignIdentity: String, announce: Bool = false,
                 mayRestart: @MainActor () async -> Bool = { true }) async {
        guard case .available(let release) = state else { return }
        progress.reset()
        progress.creep(from: 0, toward: UpdateProgress.Milestone.prepared)
        state = .downloading
        do {
            let zipURL = try await download(release.assetURL) { [weak self] received, total in
                Task { @MainActor in self?.progress.download(received: received, total: total) }
            }
            state = .verifying
            progress.creep(from: UpdateProgress.Milestone.downloaded, toward: UpdateProgress.Milestone.verified)
            guard let checksumsURL = release.checksumsURL else { throw UpdaterError.missingChecksum }
            try await verifyChecksum(of: zipURL, against: checksumsURL)
            try await verifySignature(of: zipURL, against: release.signatureURL)
            state = .installing
            progress.creep(from: UpdateProgress.Milestone.verified, toward: UpdateProgress.Milestone.installed)
            let staging = zipURL.deletingLastPathComponent().appendingPathComponent("unpacked", isDirectory: true)
            try? FileManager.default.removeItem(at: staging)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try run("/usr/bin/ditto", ["-x", "-k", zipURL.path, staging.path])
            guard let newApp = try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }) else { throw UpdaterError.noAppInArchive }
            guard let certificateURL = Bundle.main.url(forResource: "ReleaseSigning", withExtension: "cer") else {
                throw ReleaseSignature.SignatureError.missingCertificate
            }
            try ReleaseSignature.verifyRelease(at: newApp, certificateURL: certificateURL)
            guard let metadata = Bundle(url: newApp)?.infoDictionary,
                  metadata["CFBundleShortVersionString"] as? String == release.version,
                  (metadata["UpdateChannel"] as? String == "dev") == Self.isDevChannel else {
                throw UpdaterError.wrongRelease
            }
            _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])
            let identity = codesignIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
            if !identity.isEmpty {
                // Nie wolno kontynuować po błędzie: utrata lokalnego podpisu zerwałaby zgodę TCC.
                guard identity != "-" else { throw UpdaterError.adHocIdentity }
                try run("/usr/bin/codesign", ["--force", "--sign", identity,
                                             "--entitlements", newApp.appendingPathComponent("Contents/Resources/Seam.entitlements").path,
                                             newApp.path])
                try ReleaseSignature.verify(at: newApp)
            }
            // A download can take long enough for the user to resume work.
            guard await mayRestart() else {
                try? FileManager.default.removeItem(at: zipURL.deletingLastPathComponent())
                progress.reset()
                state = .available(release)
                return
            }
            progress.creep(from: UpdateProgress.Milestone.installed, toward: UpdateProgress.Milestone.handedOff)
            if announce { Self.saveRelaunchMarker(for: release) }
            try swapAndRelaunch(newApp: newApp)
        } catch {
            Self.clearRelaunchMarker()
            progress.reset()
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Po ponownym uruchomieniu

    private static let relaunchVersionKey = "Updater.relaunchVersion"
    private static let relaunchNotesKey = "Updater.relaunchNotes"

    private static func saveRelaunchMarker(for release: Release) {
        UserDefaults.standard.set(release.version, forKey: relaunchVersionKey)
        UserDefaults.standard.set(release.notes, forKey: relaunchNotesKey)
    }

    private static func clearRelaunchMarker() {
        UserDefaults.standard.removeObject(forKey: relaunchVersionKey)
        UserDefaults.standard.removeObject(forKey: relaunchNotesKey)
    }

    /// The update this launch completes, once: only when the running version is the one installed.
    static func consumeRelaunchMarker() -> (version: String, notes: String)? {
        defer { clearRelaunchMarker() }
        guard let version = UserDefaults.standard.string(forKey: relaunchVersionKey),
              version == currentVersion else { return nil }
        return (version, UserDefaults.standard.string(forKey: relaunchNotesKey) ?? "")
    }

    /// Finishes the bar the previous process left at the hand-off point.
    func celebrate(version: String, notes: String) {
        installedNotes = notes.isEmpty ? nil : notes
        state = .updated(version)
        progress.reset()
        progress.advance(to: UpdateProgress.Milestone.handedOff)
        Task { @MainActor [progress] in
            try? await Task.sleep(for: .milliseconds(500))
            progress.finish()
        }
    }

    /// States for `--ui-preview --ui-update <name>` screenshots; no network, nothing installed.
    func showPreview(_ name: String) {
        let page = URL(string: "https://github.com/\(Self.owner)/\(Self.repo)/releases")!
        let release = Release(version: "2.1.20", tag: "dev-build", notes: Self.previewNotes, pageURL: page,
                              assetURL: page, checksumsURL: page, signatureURL: page)
        progress.reset()
        switch name {
        case "available": state = .available(release)
        case "downloading":
            state = .downloading
            progress.download(received: 21_400_000, total: 48_200_000)
        case "installing":
            state = .installing
            progress.advance(to: 0.8)
        case "updated": celebrate(version: Self.currentVersion, notes: Self.previewNotes)
        case "failed": state = .failed(L10n.text("Brak połączenia z GitHubem", "Cannot reach GitHub"))
        default: state = .upToDate("18:04")
        }
    }

    private static let previewNotes = """
    Wspólne wydanie testowe macOS (Apple Silicon i Intel) oraz Windows x64.

    ## Nowe w 2.1.20 — ustawienia jak w nowoczesnych aplikacjach

    - Ustawienia przejmują okno: lista stron z wyszukiwarką i przyciskiem **Wstecz**.
    - Pasek aktualizacji z etapami pobierania, weryfikacji i instalacji.
    - Po ponownym uruchomieniu aplikacja pokazuje, co się zmieniło.

    ## Poprawki

    - Pasek tytułu nie zasłania już treści przy przewijaniu.

    ## Aktualizacja

    Aplikacje z kanału testowego wykryją tę wersję automatycznie.
    """

    private func download(_ url: URL, progress: @escaping (Int64, Int64) -> Void) async throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Seam-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(Self.assetName)
        var request = URLRequest(url: url)
        request.setValue("Seam-macOS/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdaterError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        if http.expectedContentLength > Self.maximumDownloadBytes {
            throw UpdaterError.downloadTooLarge
        }
        let total = Double(http.expectedContentLength)
        var received = 0
        var buffer = [UInt8]()
        buffer.reserveCapacity(1 << 20)
        let handle: FileHandle
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        handle = try FileHandle(forWritingTo: dest)
        defer { try? handle.close() }
        var lastReport = Date()
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 20 {
                handle.write(Data(buffer))
                received += buffer.count
                if received > Self.maximumDownloadBytes { throw UpdaterError.downloadTooLarge }
                buffer.removeAll(keepingCapacity: true)
                if Date().timeIntervalSince(lastReport) > 0.1 {
                    lastReport = Date()
                    progress(Int64(received), Int64(max(total, 0)))
                }
            }
        }
        if !buffer.isEmpty {
            received += buffer.count
            if received > Self.maximumDownloadBytes { throw UpdaterError.downloadTooLarge }
            handle.write(Data(buffer))
        }
        progress(Int64(received), Int64(received))
        return dest
    }

    private func verifyChecksum(of file: URL, against checksumsURL: URL) async throws {
        let (data, _) = try await URLSession.shared.data(from: checksumsURL)
        let text = String(decoding: data, as: UTF8.self)
        guard let entry = text.split(separator: "\n").map({ $0.split(whereSeparator: { $0.isWhitespace }) })
            .first(where: { $0.count == 2 && $0[1] == Self.assetName }),
              let expected = entry.first,
              expected.count == 64, expected.allSatisfy({ $0.isHexDigit }) else { throw UpdaterError.missingChecksum }
        let digest = try ArtifactSignature.sha256Hex(of: file)
        guard digest == String(expected).lowercased() else { throw UpdaterError.checksumMismatch }
    }

    private func verifySignature(of file: URL, against signatureURL: URL) async throws {
        var request = URLRequest(url: signatureURL)
        request.setValue("Seam-macOS/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdaterError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        if http.expectedContentLength > 256 { throw UpdaterError.invalidSignatureFile }
        var signature = Data()
        signature.reserveCapacity(80)
        for try await byte in bytes {
            guard signature.count < 256 else { throw UpdaterError.invalidSignatureFile }
            signature.append(byte)
        }
        try ArtifactSignature.verify(file: file, signatureData: signature)
    }

    private func swapAndRelaunch(newApp: URL) throws {
        let current = Bundle.main.bundleURL
        let parent = current.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw UpdaterError.notWritable(parent.path)
        }
        // The new bundle keeps its own name, so an install still called BorderlessMouse.app becomes Seam.app.
        let target = parent.appendingPathComponent(newApp.lastPathComponent)
        guard target == current || !FileManager.default.fileExists(atPath: target.path) else {
            throw UpdaterError.notWritable(target.path)
        }
        let script = """
        #!/bin/sh
        PID="$1"; NEW="$2"; APP="$3"; TARGET="$4"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done
        OLD="$APP.old-$$"
        mv "$APP" "$OLD" || exit 1
        if ! mv "$NEW" "$TARGET"; then mv "$OLD" "$APP"; exit 1; fi
        if open -n "$TARGET"; then
          rm -rf "$OLD"
        else
          rm -rf "$TARGET"
          mv "$OLD" "$APP"
          open -n "$APP"
          exit 1
        fi
        """
        let scriptURL = newApp.deletingLastPathComponent().appendingPathComponent("swap.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path, String(ProcessInfo.processInfo.processIdentifier), newApp.path, current.path, target.path]
        try process.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }

    @discardableResult
    private func run(_ tool: String, _ args: [String]) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let err = Pipe()
        p.standardError = err
        p.standardOutput = err
        try p.run()
        // Opróżniamy wspólny potok przed waitUntilExit, żeby narzędzie nie utknęło przy pełnym buforze.
        let output = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let msg = String(decoding: output, as: UTF8.self)
            throw UpdaterError.tool(tool, msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return p.terminationStatus
    }

    enum UpdaterError: LocalizedError {
        case http(Int)
        case malformed
        case wrongRelease
        case noAppInArchive
        case missingChecksum
        case missingSignature
        case invalidSignatureFile
        case checksumMismatch
        case downloadTooLarge
        case adHocIdentity
        case notWritable(String)
        case tool(String, String)

        var errorDescription: String? {
            switch self {
            case .http(let code): return L10n.text("GitHub odpowiedział kodem \(code)", "GitHub returned status \(code)")
            case .malformed: return L10n.text("Nieoczekiwana odpowiedź GitHuba", "Unexpected GitHub response")
            case .wrongRelease: return L10n.text("Pobrana aplikacja ma inną wersję lub kanał aktualizacji. Spróbuj ponownie.", "The downloaded app has a different version or update channel. Try again.")
            case .noAppInArchive: return L10n.text("W archiwum nie ma aplikacji", "The archive does not contain the app")
            case .missingChecksum: return L10n.text("W wydaniu brakuje prawidłowej sumy SHA-256 dla aplikacji", "The release has no valid SHA-256 checksum for the app")
            case .missingSignature: return L10n.text("W wydaniu brakuje podpisu kryptograficznego aplikacji", "The release has no cryptographic signature for the app")
            case .invalidSignatureFile: return L10n.text("Plik podpisu aktualizacji jest nieprawidłowy", "The update signature file is invalid")
            case .checksumMismatch: return L10n.text("Suma SHA-256 pobranego pliku nie zgadza się z wydaniem", "The downloaded file does not match the release SHA-256 checksum")
            case .downloadTooLarge: return L10n.text("Plik aktualizacji przekracza limit 300 MiB", "The update exceeds the 300 MiB limit")
            case .adHocIdentity: return L10n.text("Podpis ad-hoc nie zachowuje uprawnień. Zostaw pole certyfikatu puste, aby użyć stałego podpisu wydawcy.", "An ad-hoc signature cannot preserve permissions. Leave the certificate field empty to use the publisher signature.")
            case .notWritable(let path): return L10n.text("Brak prawa zapisu do \(path) – przenieś aplikację np. do ~/Applications", "Cannot write to \(path); move the app to a writable location such as ~/Applications")
            case .tool(let tool, let msg): return "\(tool): \(msg)"
            }
        }
    }
}

/// Install progress as one bar that never moves back. Each step owns a slice of it; steps
/// that report nothing ease toward the end of their slice so the bar never looks stuck.
@MainActor
final class UpdateProgress: ObservableObject {
    enum Milestone {
        static let prepared = 0.04
        static let downloaded = 0.60
        static let verified = 0.72
        static let installed = 0.86
        /// Where the old process stops; the relaunched app sweeps on to the end.
        static let handedOff = 0.92
    }

    @Published private(set) var value: Double = 0
    @Published private(set) var receivedBytes: Int64 = 0
    @Published private(set) var totalBytes: Int64 = 0
    private var creepTask: Task<Void, Never>?

    func reset() {
        creepTask?.cancel()
        value = 0
        receivedBytes = 0
        totalBytes = 0
    }

    /// Forward only: a late or repeated report never pulls the bar back.
    func advance(to target: Double) {
        let clamped = min(max(target, 0), 1)
        if clamped > value { value = clamped }
    }

    func download(received: Int64, total: Int64) {
        creepTask?.cancel()
        receivedBytes = received
        totalBytes = total
        guard total > 0 else { return }
        let fraction = min(Double(received) / Double(total), 1)
        advance(to: Milestone.prepared + (Milestone.downloaded - Milestone.prepared) * fraction)
    }

    /// Eases from `floor` toward `ceiling` without reaching it.
    func creep(from floor: Double, toward ceiling: Double) {
        creepTask?.cancel()
        advance(to: floor)
        creepTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                guard let self, !Task.isCancelled else { return }
                self.advance(to: self.value + (ceiling - self.value) * 0.07)
            }
        }
    }

    func finish() {
        creepTask?.cancel()
        advance(to: 1)
    }
}
