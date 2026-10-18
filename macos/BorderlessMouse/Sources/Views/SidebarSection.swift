import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case connection, permissions, control, audio, clipboard, windows, settings, log

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connection: return L10n.localized("Połączenie")
        case .audio: return L10n.text("Dźwięk", "Audio")
        case .clipboard: return L10n.text("Schowek", "Clipboard")
        case .windows: return L10n.text("Okna", "Windows")
        case .permissions: return L10n.localized("Uprawnienia")
        case .control: return L10n.text("Klawiatura i mysz", "Keyboard & mouse")
        case .settings: return L10n.localized("Ustawienia")
        case .log: return L10n.localized("Dziennik")
        }
    }

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
