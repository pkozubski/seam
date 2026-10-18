import SwiftUI

struct SidebarRow: View {
    let section: SidebarSection
    let selected: Bool
    var attention = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            SeamIconTile(name: "icon-\(section.rawValue)", size: 30, active: selected)
            Text(section.title)
                .font(.body.weight(selected ? .semibold : .regular))
            Spacer(minLength: 0)
            if attention {
                Circle().fill(.orange).frame(width: 7, height: 7)
                    .accessibilityLabel(L10n.text("Wymaga uwagi", "Needs attention"))
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(.primary.opacity(hovering && !selected ? 0.045 : 0), in: RoundedRectangle(cornerRadius: 8))
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}
