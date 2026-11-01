import SwiftUI

/// Osobne, natywne okno Ustawień (scena `Settings`, ⌘,): systemowy pasek boczny z wyszukiwaniem,
/// kartą licencji, kafelkami i listą, a po prawej strona ze zgrupowanymi kartami.
struct SettingsWindow: View {
    @Environment(AppState.self) private var state
    @ObservedObject private var navigation = SettingsNavigation.shared

    var body: some View {
        NavigationSplitView {
            SettingsWindowSidebar(navigation: navigation)
                .navigationSplitViewColumnWidth(min: 230, ideal: 250, max: 300)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsChrome.sectionSpacing) {
                    switch navigation.pane {
                    case .general: GeneralSettingsPane()
                    case .language: LanguageSettingsPane()
                    case .license: LicenseSettingsPane()
                    case .updates: UpdatesSettingsPane(updater: state.updater)
                    case .advanced: AdvancedSettingsPane()
                    case .about: AboutSettingsPane()
                    }
                }
                .frame(maxWidth: SettingsChrome.columnWidth, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            .id(navigation.pane)
            .navigationTitle(navigation.pane.title)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    ControlGroup {
                        Button(action: navigation.goBack) { Image(systemName: "chevron.left") }
                            .disabled(!navigation.canGoBack)
                            .help(L10n.text("Back", pl: "Wstecz"))
                        Button(action: navigation.goForward) { Image(systemName: "chevron.right") }
                            .disabled(!navigation.canGoForward)
                            .help(L10n.text("Forward", pl: "Dalej"))
                    }
                    .controlGroupStyle(.navigation)
                }
                ToolbarItem(placement: .primaryAction) {
                    SettingsUpdateButton(updater: state.updater, install: state.installUpdate)
                }
            }
        }
        .frame(minWidth: 780, idealWidth: 840, minHeight: 560, idealHeight: 640)
        .preferredColorScheme(.dark)
        .tint(DesignTokens.accent)
    }
}

/// „Update & restart” w pasku narzędzi, tylko gdy aktualizacja czeka.
private struct SettingsUpdateButton: View {
    @ObservedObject var updater: Updater
    let install: () -> Void

    var body: some View {
        if case .available = updater.state {
            Button(action: install) {
                Label(L10n.text("Update & restart", pl: "Zaktualizuj i uruchom ponownie"), systemImage: "arrow.down.circle.fill")
                    .labelStyle(.titleAndIcon)
            }
            .modifier(NativeActionStyle(prominent: true))
        }
    }
}

// MARK: - Pasek boczny

private struct SettingsWindowSidebar: View {
    @Environment(AppState.self) private var state
    @ObservedObject var navigation: SettingsNavigation
    @State private var query = ""

    private static let tiles: [SettingsPane] = [.general, .language, .updates, .advanced]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSearchField(text: $query)
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    LicenseAccountCard(selected: navigation.pane == .license) { navigation.select(.license) }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(Self.tiles) { pane in
                            SettingsTile(pane: pane, selected: navigation.pane == pane,
                                         updater: pane == .updates ? state.updater : nil) { navigation.select(pane) }
                        }
                    }
                    VStack(spacing: 2) {
                        MainWindowLink(section: .permissions, symbol: "lock.shield.fill",
                                       tint: Color(red: 0.36, green: 0.68, blue: 0.40))
                        MainWindowLink(section: .log, symbol: "list.bullet.rectangle.fill",
                                       tint: Color(red: 0.55, green: 0.55, blue: 0.60))
                    }
                    SettingsListRow(pane: .about, selected: navigation.pane == .about) { navigation.select(.about) }
                } else {
                    let results = SettingsPane.allCases.filter { $0.matches(query) }
                    VStack(spacing: 2) {
                        ForEach(results) { pane in
                            SettingsListRow(pane: pane, selected: navigation.pane == pane) { navigation.select(pane) }
                        }
                    }
                    if results.isEmpty {
                        Text(L10n.text("No results", pl: "Brak wyników"))
                            .font(.callout).foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.never)
    }
}

/// Karta na górze paska bocznego, jak konto w ustawieniach Droppy: stan Seam Pro.
private struct LicenseAccountCard: View {
    @Environment(AppState.self) private var state
    let selected: Bool
    let action: () -> Void

    private var title: String {
        switch state.license.entitlement.state {
        case .pro: return "Seam Pro"
        case .trial: return L10n.text("Seam Pro trial", pl: "Seam Pro – okres próbny")
        default: return "Seam Free"
        }
    }

    private var subtitle: String {
        let entitlement = state.license.entitlement
        switch entitlement.state {
        case .pro: return state.license.license?.customerEmail ?? L10n.text("License active", pl: "Licencja aktywna")
        case .trial: return L10n.text("\(entitlement.trialDaysLeft ?? 0) days left", pl: "Zostało dni: \(entitlement.trialDaysLeft ?? 0)")
        case .free: return L10n.text("Try Pro free for 7 days", pl: "Wypróbuj Pro przez 7 dni")
        default: return L10n.text("Upgrade to Pro", pl: "Przejdź na Pro")
        }
    }

    var body: some View {
        SidebarCardButton(selected: selected, action: action) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().interpolation(.high).scaledToFit()
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(verbatim: title).font(.headline)
                        if state.license.entitlement.state == .pro { ProBadge() }
                    }
                    Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
        }
    }
}

/// Kafelek 2×2: kolorowa ikona u góry, nazwa u dołu.
private struct SettingsTile: View {
    let pane: SettingsPane
    let selected: Bool
    let updater: Updater?
    let action: () -> Void

    var body: some View {
        SidebarCardButton(selected: selected, action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    PaneIcon(symbol: pane.symbol, tint: pane.tint, size: 26)
                    Spacer(minLength: 0)
                    if let updater { UpdateBadge(updater: updater) }
                }
                Text(verbatim: pane.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Wiersz listy (O programie, wyniki wyszukiwania); zaznaczenie w kolorze akcentu jak w Droppy.
private struct SettingsListRow: View {
    let pane: SettingsPane
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                PaneIcon(symbol: pane.symbol, tint: selected ? .white.opacity(0.25) : pane.tint, size: 22)
                Text(verbatim: pane.title).font(.body.weight(selected ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.white.opacity(hovering ? 0.06 : 0)))
            }
            .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Wiersz, który otwiera stronę okna głównego (Uprawnienia, Dziennik) zamiast powielać ją w Ustawieniach.
private struct MainWindowLink: View {
    @Environment(\.openWindow) private var openWindow
    let section: SidebarSection
    let symbol: String
    let tint: Color
    @State private var hovering = false

    var body: some View {
        Button {
            MainWindowRouter.shared.requested = section
            openWindow(id: "main")
        } label: {
            HStack(spacing: 10) {
                PaneIcon(symbol: symbol, tint: tint, size: 22)
                Text(verbatim: section.title)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(hovering ? 0.06 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(L10n.text("Opens in the main window", pl: "Otwiera się w oknie głównym"))
    }
}

/// Wspólna ramka kart w pasku bocznym: delikatne tło, zaznaczenie obwódką i tłem akcentu.
private struct SidebarCardButton<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button(action: action) {
            content
                .contentShape(shape)
                .background(shape.fill(selected ? Color.accentColor.opacity(0.28) : Color.white.opacity(hovering ? 0.09 : 0.06)))
                .overlay(shape.strokeBorder(selected ? Color.accentColor.opacity(0.7) : Color.white.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Ikona strony: biały symbol na kolorowej płytce.
private struct PaneIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.7)], startPoint: .top, endPoint: .bottom)))
            .accessibilityHidden(true)
    }
}

struct SettingsSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(L10n.text("Search settings", pl: "Szukaj w ustawieniach"), text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("Clear", pl: "Wyczyść"))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Capsule().fill(Color.white.opacity(0.07)))
    }
}
