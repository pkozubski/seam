import SwiftUI

/// A compact rail gives the visual guide the width of an internal feature tab.
struct WindowsSidebar: View {
    @Binding var selection: SidebarSection?

    var body: some View {
        VStack(spacing: 12) {
            ForEach([SidebarSection.connection, .control, .audio, .clipboard, .windows, .permissions, .log]) { section in
                Button { selection = section } label: {
                    SeamArtwork(name: section.iconName)
                        .frame(width: 24, height: 24).frame(width: 48, height: 48)
                        .background(selection == section ? Color.white.opacity(0.13) : .clear,
                                    in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain).help(section.title).accessibilityLabel(section.title)
                .accessibilityAddTraits(selection == section ? .isSelected : [])
            }
            Spacer()
            Button { SettingsNavigation.shared.present() } label: {
                SeamArtwork(name: SidebarSection.settings.iconName).frame(width: 24, height: 24).frame(width: 48, height: 48)
            }
            .buttonStyle(.plain).help(L10n.text("Ustawienia", "Settings"))
            .accessibilityLabel(L10n.text("Ustawienia", "Settings"))
        }
        .padding(.vertical, 20).frame(maxWidth: .infinity)
    }
}
