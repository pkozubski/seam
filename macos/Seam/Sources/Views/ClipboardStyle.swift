import SwiftUI

/// Kolory strony Schowek: stonowany bursztyn (kolory z zaakceptowanej makiety A).
enum ClipboardTokens {
    static let top = Color(red: 0x2A / 255, green: 0x18 / 255, blue: 0x06 / 255)
    static let edge = Color(red: 0x12 / 255, green: 0x0A / 255, blue: 0x03 / 255)
    static let center = Color(red: 0x6E / 255, green: 0x42 / 255, blue: 0x12 / 255)
    static let glow = Color(red: 0xC8 / 255, green: 0x86 / 255, blue: 0x2A / 255)
    static let accent = Color(red: 0xD9 / 255, green: 0x92 / 255, blue: 0x2C / 255)
    static let light = Color(red: 0xFF / 255, green: 0xD5 / 255, blue: 0x8A / 255)
    static let mutedText = Color(red: 0xF0 / 255, green: 0xD9 / 255, blue: 0xB5 / 255)
    static let cardBorder = Color(red: 0xFF / 255, green: 0xD9 / 255, blue: 0xA0 / 255).opacity(0.2)
}

/// Bursztynowe tło na całe okno dla zakładki Schowek.
struct ClipboardBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [ClipboardTokens.top, ClipboardTokens.edge], startPoint: .top, endPoint: .bottom)
            // Ciepłe światło za schowkiem po lewej.
            EllipticalGradient(colors: [ClipboardTokens.center, .clear],
                               center: UnitPoint(x: 0.36, y: 0.42), endRadiusFraction: 0.55)
            // Łagodna złota poświata w prawym dolnym rogu.
            EllipticalGradient(colors: [ClipboardTokens.glow.opacity(0.6), ClipboardTokens.glow.opacity(0.15), .clear],
                               center: UnitPoint(x: 0.95, y: 1.05), endRadiusFraction: 0.5)
            Image(nsImage: SeamBackdrop.grainTile)
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Grafika strony: szklany schowek, z którego wylatują karta tekstu i karta zdjęcia po smugach światła.
/// Trzy osobne obrazy składane tutaj; położenia są ułamkami szerokości, więc układ skaluje się z oknem.
struct ClipboardHero: View {
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            ZStack(alignment: .topLeading) {
                SeamArtwork(name: "hero-clipboard-board")
                    .frame(width: w * 0.58)
                    .shadow(color: ClipboardTokens.glow.opacity(0.45), radius: 30)
                    .position(x: w * 0.33, y: w * 0.47)
                trails(width: w)
                SeamArtwork(name: "hero-clipboard-text")
                    .frame(width: w * 0.36)
                    .shadow(color: ClipboardTokens.light.opacity(0.35), radius: 18)
                    .position(x: w * 0.80, y: w * 0.34)
                SeamArtwork(name: "hero-clipboard-photo")
                    .frame(width: w * 0.38)
                    .shadow(color: ClipboardTokens.light.opacity(0.35), radius: 18)
                    .position(x: w * 0.64, y: w * 0.62)
            }
        }
        .aspectRatio(1.15, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// Smugi światła ze środka schowka do obu kart: miękka poświata pod cienką jasną linią.
    private func trails(width w: CGFloat) -> some View {
        let path = Path { path in
            for (end, bend) in [(CGPoint(x: 0.70, y: 0.36), CGPoint(x: 0.42, y: 0.26)),
                                (CGPoint(x: 0.56, y: 0.58), CGPoint(x: 0.36, y: 0.50)),
                                (CGPoint(x: 0.66, y: 0.46), CGPoint(x: 0.40, y: 0.36))] {
                path.move(to: CGPoint(x: w * 0.20, y: w * 0.56))
                path.addQuadCurve(to: CGPoint(x: w * end.x, y: w * end.y), control: CGPoint(x: w * bend.x, y: w * bend.y))
            }
        }
        let fade = LinearGradient(colors: [ClipboardTokens.light.opacity(0), ClipboardTokens.light.opacity(0.7), .white.opacity(0.95)],
                                  startPoint: .leading, endPoint: .trailing)
        return ZStack {
            path.stroke(fade, style: StrokeStyle(lineWidth: 16, lineCap: .round)).blur(radius: 12)
            path.stroke(fade, style: StrokeStyle(lineWidth: 5, lineCap: .round)).blur(radius: 3)
            path.stroke(fade, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        }
        .allowsHitTesting(false)
    }
}

/// Mała bursztynowa szklana płytka z symbolem, do listy typów danych.
struct ClipboardTypeIcon: View {
    let symbol: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(ClipboardTokens.light)
            .frame(width: 36, height: 36)
            .background(LinearGradient(colors: [ClipboardTokens.glow.opacity(0.45), ClipboardTokens.center.opacity(0.6)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), in: shape)
            .overlay(shape.strokeBorder(ClipboardTokens.cardBorder, lineWidth: 1))
            .accessibilityHidden(true)
    }
}
