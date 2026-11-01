import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case connection, permissions, control, audio, clipboard, windows, settings, log

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connection: return L10n.localized("Connection")
        case .audio: return L10n.text("Audio", pl: "Dźwięk")
        case .clipboard: return L10n.text("Clipboard", pl: "Schowek")
        case .windows: return L10n.text("Windows", pl: "Okna")
        case .permissions: return L10n.localized("Permissions")
        case .control: return L10n.text("Keyboard & mouse", pl: "Klawiatura i mysz")
        case .settings: return L10n.localized("Settings")
        case .log: return L10n.localized("Diagnostics")
        }
    }

    /// Ikona paska bocznego bez płytki (`assets/seam/nav-*.png`, wyrównane optycznie, z marginesem w pliku).
    var iconName: String { "nav-\(rawValue)" }

    var systemImage: String {
        switch self {
        case .connection: return "link"
        case .audio: return "speaker.wave.2"
        case .clipboard: return "clipboard"
        case .windows: return "macwindow.on.rectangle"
        case .permissions: return "hand.raised"
        case .control: return "computermouse"
        case .settings: return "gearshape"
        case .log: return "list.bullet.rectangle"
        }
    }
}
