import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var state
    @Binding var selection: SidebarSection?

    @Namespace private var selectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool

    /// Kolejność dla strzałek ↑/↓ (taka sama jak na ekranie).
    private static let order: [SidebarSection] = [.connection, .control, .audio, .clipboard, .windows, .permissions, .log]

    var body: some View {
        VStack(spacing: 0) {
            SidebarBrand()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    row(.connection)
                    header(L10n.text("Funkcje", "Features"))
                    ForEach([SidebarSection.control, .audio, .clipboard, .windows]) { row($0) }
                    header(L10n.text("System", "System"))
                    row(.permissions, attention: missingPermissions > 0)
                    row(.log)
                }
                .padding(.horizontal, 12)
            }
            .scrollIndicators(.never)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(.upArrow) { step(-1) }
            .onKeyPress(.downArrow) { step(1) }

            VStack(alignment: .leading, spacing: 10) {
                Button { SettingsNavigation.shared.present() } label: {
                    SidebarRow(section: .settings, selected: false)
                        .overlay(alignment: .trailing) { UpdateBadge(updater: state.updater).padding(.trailing, 6) }
                }
                .buttonStyle(.plain)
                .help(L10n.text("Ustawienia (⌘,)", "Settings (⌘,)"))
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                    Label(state.settings.deviceName, systemImage: "laptopcomputer")
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Label("Tylko w sieci lokalnej", systemImage: "lock.fill")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("seam · \(Updater.currentVersion)")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 18)
        }
    }

    private func row(_ section: SidebarSection, attention: Bool = false) -> some View {
        Button { select(section) } label: {
            SidebarRow(section: section, selected: selection == section, attention: attention,
                       namespace: selectionNamespace)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == section ? .isSelected : [])
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.top, 18)
            .padding(.bottom, 4)
    }

    private func select(_ section: SidebarSection) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) { selection = section }
    }

    private func step(_ offset: Int) -> KeyPress.Result {
        let index = Self.order.firstIndex(of: selection ?? .connection) ?? 0
        let next = min(max(index + offset, 0), Self.order.count - 1)
        guard next != index else { return .handled }
        select(Self.order[next])
        return .handled
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
