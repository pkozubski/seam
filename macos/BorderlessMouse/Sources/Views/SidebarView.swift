import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var state: AppState
    @Binding var selection: SidebarSection?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                SeamArtwork(name: "seam-icon").frame(width: 46, height: 46).accessibilityHidden(true)
                Text("seam").font(.system(size: 26, weight: .medium)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 22)

            List(selection: $selection) {
                Section {
                    ForEach([SidebarSection.connection, .control, .audio, .clipboard, .windows]) { section in
                        SidebarRow(section: section, selected: selection == section)
                            .tag(section)
                    }
                }
                Section {
                    SidebarRow(section: .permissions, selected: selection == .permissions).tag(SidebarSection.permissions)
                    SidebarRow(section: .log, selected: selection == .log)
                        .tag(SidebarSection.log)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            VStack(alignment: .leading, spacing: 10) {
                Button { selection = .settings } label: { SidebarRow(section: .settings, selected: selection == .settings) }.buttonStyle(.plain)
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
        .background(DesignTokens.canvas)
        .navigationSplitViewColumnWidth(min: 215, ideal: 230, max: 270)
    }
}
