import SwiftUI

struct SidebarRow: View {
    let section: SidebarSection
    let selected: Bool
    var attention = false
    var namespace: Namespace.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            SeamArtwork(name: section.iconName)
                .frame(width: 26, height: 26)
            Text(section.title)
                .font(.body.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected || hovering ? .primary : .secondary)
            Spacer(minLength: 0)
            if attention {
                Circle().fill(.orange).frame(width: 7, height: 7)
                    .accessibilityLabel(L10n.text("Wymaga uwagi", "Needs attention"))
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 46)
        .contentShape(Rectangle())
        .background { SidebarRowBackground(selected: selected, hovering: hovering, namespace: namespace) }
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}
