import AppKit
import SwiftUI

/// Strony osobnego okna Ustawień (scena `Settings`, ⌘,).
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, language, license, updates, advanced, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return L10n.text("General", pl: "Ogólne")
        case .language: return L10n.text("Language", pl: "Język")
        case .license: return L10n.text("License", pl: "Licencja")
        case .updates: return L10n.text("Updates", pl: "Aktualizacje")
        case .advanced: return L10n.text("Advanced", pl: "Zaawansowane")
        case .about: return L10n.text("About", pl: "O programie")
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .language: return "globe"
        case .license: return "checkmark.seal.fill"
        case .updates: return "arrow.down.circle.fill"
        case .advanced: return "slider.horizontal.3"
        case .about: return "info.circle.fill"
        }
    }

    /// Kolor ikony w pasku bocznym (kafelki jak w ustawieniach Droppy).
    var tint: Color {
        switch self {
        case .general: return Color(red: 0.55, green: 0.60, blue: 0.70)
        case .language: return Color(red: 0.20, green: 0.72, blue: 0.70)
        case .license: return Color(red: 0.96, green: 0.62, blue: 0.36)
        case .updates: return Color(red: 0.25, green: 0.55, blue: 1.00)
        case .advanced: return Color(red: 0.62, green: 0.45, blue: 0.95)
        case .about: return Color(red: 0.45, green: 0.50, blue: 0.62)
        }
    }

    /// Extra words the sidebar search matches, in both languages.
    private var keywords: [String] {
        switch self {
        case .general: return ["nazwa", "name", "mac", "logowanie", "login", "autostart", "okno", "window", "menu"]
        case .language: return ["język", "language", "english", "polski", "angielski", "polish"]
        case .license: return ["pro", "licencja", "license", "klucz", "key", "trial", "próbny", "kup", "buy", "zakup", "purchase"]
        case .updates: return ["wersja", "version", "aktualizacja", "update", "kanał", "channel", "github", "restart"]
        case .advanced: return ["port", "tcp", "sieć", "network", "certyfikat", "certificate", "podpis", "signing", "codesign"]
        case .about: return ["wersja", "version", "zmiany", "changelog", "prywatność", "privacy", "licencje", "notices", "pomoc", "help"]
        }
    }

    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        return ([title] + keywords).contains { $0.localizedCaseInsensitiveContains(needle) }
    }
}

/// Która strona okna Ustawień jest otwarta, z historią dla Wstecz/Dalej. Wspólne, żeby ⌘,, przycisk
/// w pasku bocznym, karta Pro i zakończona aktualizacja otwierały właściwą stronę.
@MainActor
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()

    @Published private(set) var pane: SettingsPane = .general
    @Published private var back: [SettingsPane] = []
    @Published private var forward: [SettingsPane] = []

    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }

    func select(_ next: SettingsPane) {
        guard next != pane else { return }
        back.append(pane)
        forward.removeAll()
        pane = next
    }

    func goBack() {
        guard let previous = back.popLast() else { return }
        forward.append(pane)
        pane = previous
    }

    func goForward() {
        guard let next = forward.popLast() else { return }
        back.append(pane)
        pane = next
    }

    /// `openSettings` ze środowiska SwiftUI, zapisany przez okno główne i pasek menu: akcja
    /// `showSettingsWindow:` przez łańcuch respondentów nie otwiera już sceny Settings w macOS 26.
    var opener: (() -> Void)?

    /// Otwiera okno Ustawień (także z kodu poza widokami) na danej stronie.
    func present(_ pane: SettingsPane? = nil) {
        if let pane { select(pane) }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let opener {
            opener()
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }
}

/// Prośba o otwarcie strony okna głównego z innego okna (np. Uprawnienia z Ustawień).
@MainActor
final class MainWindowRouter: ObservableObject {
    static let shared = MainWindowRouter()
    @Published var requested: SidebarSection?
}
