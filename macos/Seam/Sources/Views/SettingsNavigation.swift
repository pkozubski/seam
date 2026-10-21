import SwiftUI

/// Pages of the settings view that takes over the main window.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, updates, advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return L10n.text("Ogólne", "General")
        case .updates: return L10n.text("Aktualizacje", "Updates")
        case .advanced: return L10n.text("Zaawansowane", "Advanced")
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .updates: return "arrow.down.circle.fill"
        case .advanced: return "slider.horizontal.3"
        }
    }

    /// Extra words the sidebar search matches, in both languages.
    private var keywords: [String] {
        switch self {
        case .general: return ["nazwa", "name", "mac", "logowanie", "login", "autostart", "okno", "window", "menu"]
        case .updates: return ["wersja", "version", "aktualizacja", "update", "kanał", "channel", "github", "restart"]
        case .advanced: return ["port", "tcp", "sieć", "network", "certyfikat", "certificate", "podpis", "signing", "codesign"]
        }
    }

    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        return ([title] + keywords).contains { $0.localizedCaseInsensitiveContains(needle) }
    }
}

/// Whether settings cover the main window and which page they show. Shared so ⌘,, the
/// sidebar button and a finished update can all open it.
@MainActor
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()

    @Published private(set) var isPresented = false
    @Published var pane: SettingsPane = .general

    func present(_ pane: SettingsPane? = nil) {
        if let pane { self.pane = pane }
        isPresented = true
    }

    func close() {
        isPresented = false
    }

    func toggle() {
        isPresented ? close() : present()
    }
}

/// ⌘, shows settings in the main window, reopening the window if it was closed.
struct SettingsCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(L10n.text("Ustawienia…", "Settings…")) {
                openWindow(id: "main")
                SettingsNavigation.shared.toggle()
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
