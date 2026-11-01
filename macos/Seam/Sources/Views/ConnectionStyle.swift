import SwiftUI

/// Kolory strony Połączenie: niebieskie tło pod grafiką `hero-connection` (cyjan → kobalt).
enum ConnectionTokens {
    static let deepTop = Color(red: 0x0B / 255, green: 0x1F / 255, blue: 0x6B / 255)
    static let deepBottom = Color(red: 0x05 / 255, green: 0x0C / 255, blue: 0x33 / 255)
    static let cobaltGlow = Color(red: 0x1A / 255, green: 0x3F / 255, blue: 0xD6 / 255)
    static let cyanGlow = Color(red: 0x2F / 255, green: 0xC8 / 255, blue: 0xFF / 255)
    static let accent = Color(red: 0x3F / 255, green: 0xB4 / 255, blue: 0xFF / 255)
}

/// Niebieskie tło na całe okno dla zakładki Połączenie, na wzór zielonego tła Okien.
struct ConnectionBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [ConnectionTokens.deepTop, ConnectionTokens.deepBottom],
                           startPoint: .topLeading, endPoint: UnitPoint(x: 1, y: 0.9))
            EllipticalGradient(colors: [ConnectionTokens.cobaltGlow.opacity(0.85), .clear],
                               center: UnitPoint(x: 0.42, y: 0.42), endRadiusFraction: 0.55)
            EllipticalGradient(colors: [ConnectionTokens.cyanGlow.opacity(0.35), .clear],
                               center: UnitPoint(x: 0.6, y: 1.05), endRadiusFraction: 0.4)
            EllipticalGradient(colors: [.black.opacity(0.35), .clear],
                               center: .bottomLeading, endRadiusFraction: 0.7)
            Image(nsImage: SeamBackdrop.grainTile)
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Gotowy kafelek funkcji (szkło z symbolem w jednym obrazie), bez grafitowej płytki `SeamIconTile`.
struct ConnectionTile: View {
    let name: String
    var size: CGFloat = 34

    var body: some View {
        SeamArtwork(name: name)
            .frame(width: size, height: size)
            .shadow(color: ConnectionTokens.cyanGlow.opacity(0.25), radius: 6, y: 2)
    }
}
