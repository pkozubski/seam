import SwiftUI

struct DeviceTile: View {
    let name: String
    let symbol: String
    let detail: String
    let active: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 42, weight: .ultraLight))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(active ? Color.accentColor : .secondary)
                .frame(height: 52)
                .accessibilityHidden(true)
            Text(name).font(.headline).lineLimit(1).help(name)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Label(active ? L10n.text("Tutaj jest kursor", "Pointer is here") : L10n.text("Gotowy do pracy", "Ready to work"),
                  systemImage: active ? "cursorarrow" : "minus")
                .font(.caption.weight(.medium))
                .foregroundStyle(active ? Color.accentColor : .secondary)
                .opacity(active ? 1 : 0)
                .accessibilityHidden(!active)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background(active ? Color.accentColor.opacity(0.07) : Color.primary.opacity(0.025),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(active ? Color.accentColor.opacity(0.3) : .clear, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
