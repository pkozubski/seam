import SwiftUI

/// Shared look of the settings pages: a centered column of titled sections, each a quiet
/// card of rows with the control on the trailing edge.
enum SettingsChrome {
    static let columnWidth: CGFloat = 680
    static let cardRadius: CGFloat = 16
    static let sectionSpacing: CGFloat = 22
    static let capsuleHeight: CGFloat = 28

    static func slide(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.32, dampingFraction: 0.9)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            SettingsCard { content }
        }
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SettingsChrome.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Color.white.opacity(0.045)))
            .overlay { shape.strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5).allowsHitTesting(false) }
    }
}

/// Title and an optional description on the left, the control on the right.
struct SettingsCardRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(.body)
                if let detail, !detail.isEmpty {
                    Text(verbatim: detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control.accessibilityLabel(Text(verbatim: title))
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 11)
        .accessibilityElement(children: .contain)
    }
}

struct SettingsRowDivider: View {
    var body: some View {
        Divider().opacity(0.6).padding(.leading, 16)
    }
}

struct SettingsSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
    }
}

/// An SF Symbol on the same graphite plate as the artwork tiles, for rows without artwork.
struct SymbolTile: View {
    let symbol: String
    var size: CGFloat = 26
    var active = false

    var body: some View {
        let plate = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: size, height: size)
            .background(plate.fill(LinearGradient(colors: active ? DesignTokens.activePlate : DesignTokens.graphitePlate,
                                                  startPoint: .top, endPoint: .bottom)))
            .overlay(plate.strokeBorder(LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.03)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Liquid Glass capsule on macOS 26, a thin material capsule before it.
    @ViewBuilder
    func glassCapsule(interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: Capsule())
        } else {
            background(.thinMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5) }
        }
    }
}
