import Foundation

enum UpdatePolicy {
    static func releasePath(isDev: Bool) -> String {
        isDev ? "releases/tags/dev-build" : "releases/latest"
    }

    static func checkInterval(isDev: Bool) -> TimeInterval {
        isDev ? 120 : 6 * 3600
    }

    /// The fixed dev tag carries its numeric version in the release title, just as on Windows.
    static func releaseVersion(tag: String, title: String, isDev: Bool) -> String? {
        guard !isDev || tag == "dev-build" else { return nil }
        let value = isDev ? String(title.split(separator: " ").last ?? "") : tag
        let version = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIWholeNumber) && Int($0) != nil }) else { return nil }
        return version
    }

    static func canAutoInstall(isDev: Bool, enabled: Bool, idleSeconds: TimeInterval,
                               sessionAllowsRestart: Bool) -> Bool {
        isDev && enabled && idleSeconds.isFinite && idleSeconds >= 60 && sessionAllowsRestart
    }
}

private extension Character {
    var isASCIIWholeNumber: Bool { isASCII && isNumber }
}
