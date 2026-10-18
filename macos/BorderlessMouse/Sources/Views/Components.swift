import SwiftUI

/// Wiersz ustawienia: tytuł + opcjonalny opis po lewej, kontrolka po prawej.
struct SettingRow<Control: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(LocalizedStringKey(title))
                    .font(.body.weight(.medium))
                if let subtitle {
                    Text(LocalizedStringKey(subtitle))
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control
                .accessibilityLabel(Text(LocalizedStringKey(title)))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.6), radius: 3)
            Text(LocalizedStringKey(text)).font(.callout.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.12)))
    }
}

struct StatusDot: View {
    let ok: Bool?
    var body: some View {
        Circle()
            .fill(ok == nil ? Color.gray : (ok! ? Color.green : Color.orange))
            .frame(width: 8, height: 8)
    }
}

struct LevelMeter: View {
    let level: Float
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(level > 0.9 ? Color.orange : Color.accentColor)
                    .frame(width: max(0, geo.size.width * CGFloat(min(level, 1))))
                    .animation(reduceMotion ? nil : .linear(duration: 0.05), value: level)
            }
        }
        .frame(height: 8)
        .accessibilityLabel(L10n.text("Poziom dźwięku", "Audio level"))
        .accessibilityValue("\(Int(max(0, min(level, 1)) * 100))%")
    }
}
