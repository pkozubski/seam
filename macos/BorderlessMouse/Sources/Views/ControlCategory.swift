import SwiftUI

enum ControlCategory: String, CaseIterable, Identifiable {
    case input, audio, display, clipboard
    var id: Self { self }
    var title: String {
        switch self {
        case .input: return L10n.text("Klawiatura i mysz", "Keyboard & mouse")
        case .audio: return L10n.text("Dźwięk", "Audio")
        case .display: return L10n.text("Ekran", "Display")
        case .clipboard: return L10n.text("Schowek", "Clipboard")
        }
    }
}
