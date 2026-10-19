import Foundation

@main
struct UpdateChecks {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    @MainActor
    static func main() throws {
        func fixture(tag: String = "dev-build", title: String = "Seam dev 2.1.5",
                     omitted: String? = nil) throws -> Data {
            let names: [String] = [Updater.assetName, Updater.checksumsName, Updater.signatureName].filter { $0 != omitted }
            return try JSONSerialization.data(withJSONObject: [
                "tag_name": tag, "name": title, "html_url": "https://github.com/pkozubski/seam/releases/tag/\(tag)",
                "assets": names.map { ["name": $0, "browser_download_url": "https://example.com/\($0)"] }
            ])
        }
        expect(UpdatePolicy.releasePath(isDev: true) == "releases/tags/dev-build", "dev channel must follow Windows 2.1.4's endpoint")
        expect(UpdatePolicy.releasePath(isDev: false) == "releases/latest", "stable channel must remain stable")
        expect(UpdatePolicy.checkInterval(isDev: true) == 120, "dev polling interval")
        expect(UpdatePolicy.checkInterval(isDev: false) == 21600, "stable polling interval")
        let dev = try Updater.parseRelease(fixture(), isDev: true)
        expect(dev?.version == "2.1.5" && dev?.tag == "dev-build", "dev version comes from the title, not the fixed tag")
        let stable = try Updater.parseRelease(fixture(tag: "v2.0.2", title: "Other title"), isDev: false)
        expect(stable?.version == "2.0.2", "stable version comes from the tag")
        expect(Updater.isNewer(dev!.version, than: "2.1.4"), "Windows's installed version must upgrade")
        expect(Updater.isNewer(dev!.version, than: "1.0.0"), "old Mac local build must upgrade")
        expect(Updater.isNewer("2.1.10", than: "2.1.9"), "compare versions numerically")
        expect(!Updater.isNewer("2.1.5", than: "2.1.5") && !Updater.isNewer("2.1.4", than: "2.1.5"), "no reinstall or downgrade")
        for invalid in ["", "dev-build", "2.1", "2.1.5-dev", "2.1.x", "2..5", "2.1.5.1"] {
            do {
                _ = try Updater.parseRelease(fixture(title: invalid), isDev: true)
                fatalError("accepted invalid release title: \(invalid)")
            } catch Updater.UpdaterError.malformed {}
        }
        do {
            _ = try Updater.parseRelease(fixture(tag: "v2.1.5"), isDev: true)
            fatalError("accepted a stable tag in dev mode")
        } catch Updater.UpdaterError.malformed {}
        for missing in [Updater.signatureName, Updater.checksumsName] {
            do {
                _ = try Updater.parseRelease(fixture(omitted: missing), isDev: true)
                fatalError("accepted an unauthenticated update")
            } catch Updater.UpdaterError.missingSignature {
                expect(missing == Updater.signatureName, "signature failure")
            } catch Updater.UpdaterError.missingChecksum {
                expect(missing == Updater.checksumsName, "checksum failure")
            }
        }
        let noMac = try Updater.parseRelease(fixture(omitted: Updater.assetName), isDev: true)
        expect(noMac == nil, "old Windows-only dev release cannot be installed on Mac")
        expect(UpdatePolicy.canAutoInstall(isDev: true, enabled: true, idleSeconds: 60, sessionAllowsRestart: true), "install after one idle minute")
        for idle in [0.0, 59.9, .nan, .infinity] {
            expect(!UpdatePolicy.canAutoInstall(isDev: true, enabled: true, idleSeconds: idle, sessionAllowsRestart: true), "do not interrupt activity or accept invalid idle time")
        }
        expect(!UpdatePolicy.canAutoInstall(isDev: false, enabled: true, idleSeconds: 120, sessionAllowsRestart: true), "stable installation stays manual")
        expect(!UpdatePolicy.canAutoInstall(isDev: true, enabled: false, idleSeconds: 120, sessionAllowsRestart: true), "honor disabled automatic updates")
        expect(!UpdatePolicy.canAutoInstall(isDev: true, enabled: true, idleSeconds: 120, sessionAllowsRestart: false), "remote input and windows must prevent restart")
        print("✓ Updates: stable/dev routing, numeric versions, required signatures and idle installation policy")
    }
}
