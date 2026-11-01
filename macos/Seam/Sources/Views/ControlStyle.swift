import SwiftUI

/// Kolory strony Klawiatura i mysz: magenta pod grafiką `hero-control` (kolory z zaakceptowanej makiety).
enum ControlTokens {
    static let edge = Color(red: 0x33 / 255, green: 0x01 / 255, blue: 0x1E / 255)
    static let center = Color(red: 0x8C / 255, green: 0x05 / 255, blue: 0x48 / 255)
    static let hotGlow = Color(red: 0xE1 / 255, green: 0x16 / 255, blue: 0x77 / 255)
    static let accent = Color(red: 0xE0 / 255, green: 0x2A / 255, blue: 0x8A / 255)
    static let mutedText = Color(red: 0xF2 / 255, green: 0xC4 / 255, blue: 0xDA / 255)
    static let cardTop = Color.white.opacity(0.09)
    static let cardBottom = Color.white.opacity(0.035)
    static let cardBorder = Color(red: 0xFF / 255, green: 0xB8 / 255, blue: 0xDC / 255).opacity(0.22)
}

/// Magentowe tło na całe okno dla zakładki Klawiatura i mysz.
struct ControlBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0x4A / 255, green: 0x00 / 255, blue: 0x28 / 255), ControlTokens.edge],
                           startPoint: .top, endPoint: .bottom)
            // Światło za grafiką po lewej.
            EllipticalGradient(colors: [ControlTokens.center, .clear],
                               center: UnitPoint(x: 0.38, y: 0.48), endRadiusFraction: 0.55)
            // Gorąca poświata w prawym dolnym rogu, jak na makiecie.
            EllipticalGradient(colors: [ControlTokens.hotGlow.opacity(0.9), ControlTokens.hotGlow.opacity(0.25), .clear],
                               center: UnitPoint(x: 0.92, y: 1.0), endRadiusFraction: 0.5)
            Image(nsImage: SeamBackdrop.grainTile)
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Szklana karta ustawień na kolorowym tle strony; obramowanie w kolorze strony.
struct TintedGlassCard<Content: View>: View {
    var border: Color = ControlTokens.cardBorder
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(.horizontal, 22).padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [ControlTokens.cardTop, ControlTokens.cardBottom],
                                       startPoint: .top, endPoint: .bottom), in: shape)
            .overlay(shape.strokeBorder(border, lineWidth: 1))
    }
}

/// Szklany przycisk-pigułka z białym tekstem na kolorowych stronach (np. „Zatrzymaj”).
struct GlassPillButtonStyle: ButtonStyle {
    var border: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Color.white.opacity(configuration.isPressed ? 0.05 : 0.1), in: Capsule())
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
            .contentShape(Capsule())
    }
}
