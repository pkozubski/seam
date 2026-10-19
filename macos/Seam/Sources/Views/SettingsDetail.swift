import SwiftUI

/// The settings page shown in place of the detail column.
struct SettingsDetail: View {
    @ObservedObject var navigation: SettingsNavigation
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsChrome.sectionSpacing) {
                HStack(alignment: .center, spacing: 12) {
                    Text(verbatim: navigation.pane.title)
                        .font(.system(size: 24, weight: .semibold))
                        .tracking(-0.4)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 12)
                    if navigation.pane == .updates {
                        UpdatePill(updater: state.updater, install: state.installUpdate)
                    }
                }
                .frame(minHeight: SettingsChrome.capsuleHeight + 4)
                switch navigation.pane {
                case .general: GeneralSettingsPane()
                case .updates: UpdatesSettingsPane(updater: state.updater)
                case .advanced: AdvancedSettingsPane()
                }
            }
            .frame(maxWidth: SettingsChrome.columnWidth, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 12)
            // Room for the status orb that overlaps the window's bottom edge.
            .padding(.bottom, 96)
            .frame(maxWidth: .infinity)
        }
        .id(navigation.pane)
        .navigationTitle(L10n.localized("Ustawienia"))
        .background {
            // Esc leaves settings, like the Back row.
            Button("", action: navigation.close)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}
