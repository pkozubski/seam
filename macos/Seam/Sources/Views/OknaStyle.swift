import SwiftUI

/// Kolory zakładki Okna: świeża zieleń liści (kolory z zaakceptowanej makiety S3). Reszta aplikacji ma własne kolory stron.
enum OknaTokens {
    static let edge = Color(red: 0x0C / 255, green: 0x1F / 255, blue: 0x08 / 255)
    static let top = Color(red: 0x16 / 255, green: 0x36 / 255, blue: 0x0C / 255)
    static let center = Color(red: 0x2F / 255, green: 0x64 / 255, blue: 0x16 / 255)
    static let glow = Color(red: 0x8C / 255, green: 0xC6 / 255, blue: 0x3F / 255)
    static let accent = Color(red: 0x7C / 255, green: 0xC4 / 255, blue: 0x3F / 255)
    static let light = Color(red: 0xC4 / 255, green: 0xEC / 255, blue: 0x8A / 255)
    static let mutedText = Color(red: 0xD2 / 255, green: 0xE6 / 255, blue: 0xC2 / 255)
    static let cardBorder = Color(red: 0xD8 / 255, green: 0xF6 / 255, blue: 0xCA / 255).opacity(0.2)
}

/// Zielone tło zakładki Okna. ContentView kładzie je pod całe okno, razem z paskiem bocznym.
struct WindowsBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [OknaTokens.top, OknaTokens.edge], startPoint: .top, endPoint: .bottom)
            // Światło za grafiką u góry, jak na makiecie.
            EllipticalGradient(colors: [OknaTokens.center.opacity(1), OknaTokens.center.opacity(0.5), .clear],
                               center: UnitPoint(x: 0.58, y: 0.2), endRadiusFraction: 0.65)
            // Łagodna poświata u dołu, pod kulą Połączono.
            EllipticalGradient(colors: [OknaTokens.glow.opacity(0.45), OknaTokens.glow.opacity(0.1), .clear],
                               center: UnitPoint(x: 0.55, y: 1.08), endRadiusFraction: 0.5)
            Image(nsImage: SeamBackdrop.grainTile)
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Grafika strony: szklane okno przechodzi przez świetlny szew z laptopa na monitor.
/// Laptop, monitor i okno to osobne obrazy; szew i smugi są rysowane tutaj, położenia to ułamki szerokości.
struct WindowsHero: View {
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            ZStack {
                SeamArtwork(name: "hero-windows-laptop")
                    .frame(width: w * 0.36)
                    .position(x: w * 0.24, y: h * 0.58)
                SeamArtwork(name: "hero-windows-monitor")
                    .frame(width: w * 0.34)
                    .position(x: w * 0.77, y: h * 0.5)
                seam(height: h).position(x: w * 0.5, y: h * 0.5)
                trails(width: w, height: h)
                SeamArtwork(name: "hero-windows-window")
                    .frame(width: w * 0.22)
                    .shadow(color: OknaTokens.glow.opacity(0.6), radius: 24)
                    .position(x: w * 0.51, y: h * 0.44)
            }
        }
        .aspectRatio(2.5, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// Pionowy szew światła między ekranami: szeroka poświata, węższy blask i cienka biała linia.
    private func seam(height: CGFloat) -> some View {
        let fade = LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.35),
                                          .init(color: .white, location: 0.7), .init(color: .clear, location: 1)],
                                  startPoint: .top, endPoint: .bottom)
        return ZStack {
            Capsule().fill(OknaTokens.glow.opacity(0.7)).frame(width: 110).blur(radius: 40)
            Capsule().fill(OknaTokens.glow).frame(width: 26).blur(radius: 12)
            Capsule().fill(OknaTokens.light).frame(width: 8).blur(radius: 4)
            Capsule().fill(Color.white).frame(width: 2.5)
        }
        // Szeroka ramka: rozmycie poświaty nie może dochodzić do krawędzi maski, bo widać wtedy pionowy pas.
        .frame(width: 320, height: height * 1.1)
        .mask(fade)
        .allowsHitTesting(false)
    }

    /// Smugi z ekranu laptopa przez okno do monitora.
    private func trails(width w: CGFloat, height h: CGFloat) -> some View {
        let path = Path { path in
            // Łuki biegną nad i pod oknem, żeby nie chowały się za nim.
            for (start, end, bend) in [(CGPoint(x: 0.34, y: 0.36), CGPoint(x: 0.68, y: 0.30), CGPoint(x: 0.5, y: 0.10)),
                                       (CGPoint(x: 0.37, y: 0.70), CGPoint(x: 0.66, y: 0.66), CGPoint(x: 0.5, y: 0.86))] {
                path.move(to: CGPoint(x: w * start.x, y: h * start.y))
                path.addQuadCurve(to: CGPoint(x: w * end.x, y: h * end.y), control: CGPoint(x: w * bend.x, y: h * bend.y))
            }
        }
        let fade = LinearGradient(colors: [OknaTokens.light.opacity(0), OknaTokens.light.opacity(0.8), OknaTokens.light.opacity(0)],
                                  startPoint: .leading, endPoint: .trailing)
        return ZStack {
            path.stroke(fade, style: StrokeStyle(lineWidth: 12, lineCap: .round)).blur(radius: 9)
            path.stroke(fade, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .allowsHitTesting(false)
    }
}

/// Numer kroku w świecącym zielonym kółku.
struct OknaStepNumber: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.system(size: 22, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(Circle().fill(RadialGradient(colors: [OknaTokens.light, OknaTokens.accent, OknaTokens.center],
                                                     center: UnitPoint(x: 0.35, y: 0.25), startRadius: 1, endRadius: 40)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
            .shadow(color: OknaTokens.glow.opacity(0.6), radius: 10)
            .accessibilityHidden(true)
    }
}
