import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var state: AppState
    @Binding var selection: SidebarSection?

    var body: some View {
        VStack(spacing: 0) {
            SidebarBrand()

            List(selection: $selection) {
                SidebarRow(section: .connection, selected: selection == .connection).tag(SidebarSection.connection)
                Section(L10n.text("Funkcje", "Features")) {
                    ForEach([SidebarSection.control, .audio, .clipboard, .windows]) { section in
                        SidebarRow(section: section, selected: selection == section)
                            .tag(section)
                    }
                }
                Section(L10n.text("System", "System")) {
                    SidebarRow(section: .permissions, selected: selection == .permissions, attention: missingPermissions > 0)
                        .tag(SidebarSection.permissions)
                    SidebarRow(section: .log, selected: selection == .log)
                        .tag(SidebarSection.log)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            VStack(alignment: .leading, spacing: 10) {
                Button { SettingsNavigation.shared.present() } label: {
                    SidebarRow(section: .settings, selected: false)
                        .overlay(alignment: .trailing) { UpdateBadge(updater: state.updater).padding(.trailing, 6) }
                }
                .buttonStyle(.plain)
                .help(L10n.text("Ustawienia (⌘,)", "Settings (⌘,)"))
                Divider()
                Label(state.settings.deviceName, systemImage: "laptopcomputer")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Label("Tylko w sieci lokalnej", systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(.secondary)
                Text("seam · \(Updater.currentVersion)")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(18)
        }
    }

    private var missingPermissions: Int {
        [!state.accessibilityGranted, state.audioPermissionGranted == false,
         state.settings.displayEnabled && !state.screenCaptureGranted].filter { $0 }.count
    }
}

/// App icon and name at the top of the sidebar, in both the main and the settings view.
struct SidebarBrand: View {
    var body: some View {
        HStack(spacing: 10) {
            // The app's own icon, so the sidebar mark always matches the Dock.
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().interpolation(.high).scaledToFit()
                .frame(width: 50, height: 50)
                .accessibilityHidden(true)
            Text("seam").font(.system(size: 26, weight: .medium)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 22)
    }
}
