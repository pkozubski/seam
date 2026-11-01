import SwiftUI

/// Kolory strony Dźwięk: spokojny fiolet (jaśniejszy i mniej nasycony niż makieta), pod grafiką `hero-audio-headphones`.
enum AudioTokens {
    static let edge = Color(red: 0x14 / 255, green: 0x0B / 255, blue: 0x38 / 255)
    static let top = Color(red: 0x22 / 255, green: 0x12 / 255, blue: 0x5E / 255)
    static let center = Color(red: 0x3B / 255, green: 0x22 / 255, blue: 0x96 / 255)
    static let glow = Color(red: 0x5A / 255, green: 0x3E / 255, blue: 0xCF / 255)
    static let accent = Color(red: 0x86 / 255, green: 0x6C / 255, blue: 0xF0 / 255)
    static let barLight = Color(red: 0xC4 / 255, green: 0xB3 / 255, blue: 0xFF / 255)
    static let mutedText = Color(red: 0xCF / 255, green: 0xC6 / 255, blue: 0xFF / 255)
    static let cardBorder = Color(red: 0xC9 / 255, green: 0xB8 / 255, blue: 0xFF / 255).opacity(0.2)
}

/// Fioletowe tło na całe okno dla zakładki Dźwięk.
struct AudioBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [AudioTokens.top, AudioTokens.edge], startPoint: .top, endPoint: .bottom)
            // Światło za słuchawkami.
            EllipticalGradient(colors: [AudioTokens.center, .clear],
                               center: UnitPoint(x: 0.58, y: 0.28), endRadiusFraction: 0.55)
            // Łagodna poświata u dołu, jak na ekranach CleanMyMac.
            EllipticalGradient(colors: [AudioTokens.glow.opacity(0.7), AudioTokens.glow.opacity(0.2), .clear],
                               center: UnitPoint(x: 0.75, y: 1.05), endRadiusFraction: 0.55)
            Image(nsImage: SeamBackdrop.grainTile)
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Fala dźwięku za słuchawkami: symetryczne świecące paski, najwyższe przy środku.
struct AudioWaveBackdrop: View {
    var barCount = 46

    var body: some View {
        Canvas { context, size in
            let step = size.width / CGFloat(barCount)
            let barWidth = max(2, step * 0.38)
            for index in 0..<barCount {
                // Pozycja od środka (0) do krawędzi (1); wysokość z dwóch sinusów, żeby fala nie była regularna.
                let t = abs(Double(index) - Double(barCount - 1) / 2) / (Double(barCount) / 2)
                let ripple = 0.55 + 0.45 * abs(sin(Double(index) * 0.9) * cos(Double(index) * 0.37))
                let height = size.height * CGFloat(pow(1 - t, 1.4) * ripple) + 4
                let rect = CGRect(x: CGFloat(index) * step + (step - barWidth) / 2, y: (size.height - height) / 2,
                                  width: barWidth, height: height)
                context.fill(Capsule().path(in: rect),
                             with: .color(AudioTokens.barLight.opacity(0.25 + 0.55 * (1 - t))))
            }
        }
        .blur(radius: 0.6)
        .shadow(color: AudioTokens.accent.opacity(0.8), radius: 10)
        .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .leading, endPoint: .trailing))
        .accessibilityHidden(true)
    }
}

/// Miernik poziomu z pasków: zapala tyle pasków, ile wynosi bieżący poziom dźwięku.
struct AudioBarMeter: View {
    let level: () -> Float
    var active: Bool
    var barCount = 48
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Bez streamu nie ma czego odświeżać; zegar 20 Hz działa tylko podczas streamowania.
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !active)) { _ in
            let value = active ? min(max(level(), 0), 1) : 0
            let lit = Int((Double(value) * Double(barCount)).rounded(.up))
            HStack(spacing: 4) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(index < lit
                              ? AnyShapeStyle(LinearGradient(colors: [AudioTokens.barLight, AudioTokens.accent],
                                                             startPoint: .top, endPoint: .bottom))
                              : AnyShapeStyle(Color.white.opacity(0.08)))
                        .shadow(color: index < lit ? AudioTokens.accent.opacity(0.6) : .clear, radius: 4)
                }
            }
            .animation(reduceMotion ? nil : .linear(duration: 0.05), value: lit)
            .accessibilityValue("\(Int(value * 100))%")
        }
        .frame(height: 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text("Poziom dźwięku", "Audio level"))
    }
}
