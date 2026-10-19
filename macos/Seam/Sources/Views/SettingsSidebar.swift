import SwiftUI

/// The sidebar while settings cover the window: back, search and the settings pages.
struct SettingsSidebar: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var navigation: SettingsNavigation
    @State private var query = ""

    private var results: [SettingsPane] {
        SettingsPane.allCases.filter { $0.matches(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarBrand()
            VStack(alignment: .leading, spacing: 2) {
                SettingsSidebarButton(title: L10n.text("Wstecz", "Back"), symbol: "chevron.left", action: navigation.close)
                    .padding(.bottom, 6)
                SettingsSearchField(text: $query)
                    .padding(.bottom, 10)
                ForEach(results) { pane in
                    SettingsNavRow(pane: pane, selected: navigation.pane == pane,
                                   updater: pane == .updates ? state.updater : nil) {
                        navigation.pane = pane
                    }
                }
                if results.isEmpty {
                    Text(L10n.text("Brak wyników", "No results"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 12)
            Spacer(minLength: 0)
            Text(verbatim: "seam · \(Updater.versionDescription)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(18)
        }
        .onChange(of: query) {
            // Keep the detail on something the filter still shows.
            if !results.contains(navigation.pane), let first = results.first { navigation.pane = first }
        }
    }
}

private struct SettingsNavRow: View {
    let pane: SettingsPane
    let selected: Bool
    let updater: Updater?
    let action: () -> Void

    var body: some View {
        SettingsSidebarItem(selected: selected, action: action) { hovering in
            SymbolTile(symbol: pane.symbol, size: 26, active: selected)
            Text(verbatim: pane.title)
                .font(.body.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected || hovering ? .primary : .secondary)
            Spacer(minLength: 0)
            if let updater { UpdateBadge(updater: updater) }
        }
    }
}

private struct SettingsSidebarButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        SettingsSidebarItem(selected: false, action: action) { hovering in
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26)
            Text(verbatim: title)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
    }
}

/// Row chrome shared by the sidebar items: a rounded fill that shows selection and hover.
private struct SettingsSidebarItem<Label: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let label: (_ hovering: Bool) -> Label
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) { label(hovering) }
                .padding(.horizontal, 8)
                .frame(minHeight: 40)
                .contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.10 : hovering ? 0.05 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: hovering)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SettingsSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(L10n.text("Szukaj w ustawieniach", "Search settings"), text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("Wyczyść", "Clear"))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Capsule().fill(Color.white.opacity(0.07)))
    }
}
