import SwiftUI

/// Zielone tokeny zakładki Okna (tokens.css z projektu), te same co w `windows/Seam/Views/Pages/WindowsPage.axaml`.
/// Reszta aplikacji zostaje grafitowa.
enum OknaTokens {
    static let mutedText = Color(red: 0xC3 / 255, green: 0xD5 / 255, blue: 0xBC / 255)
    static let cardTop = Color(red: 0xDE / 255, green: 0xF5 / 255, blue: 0xC9 / 255).opacity(0x3D / 255)
    static let cardBottom = Color(red: 0xBE / 255, green: 0xE0 / 255, blue: 0xB8 / 255).opacity(0x1C / 255)
    static let cardBorder = Color(red: 0xD8 / 255, green: 0xF6 / 255, blue: 0xCA / 255).opacity(0x38 / 255)
    static let divider = Color(red: 0xD8 / 255, green: 0xF6 / 255, blue: 0xCA / 255).opacity(0x26 / 255)
    static let switchOn = Color(red: 0x45 / 255, green: 0xDB / 255, blue: 0x30 / 255)
    static let stepNumber = Color(red: 0x9B / 255, green: 0xE8 / 255, blue: 0x8A / 255)
    static let buttonText = Color(red: 0xF2 / 255, green: 0xF8 / 255, blue: 0xE6 / 255)
    static let accentText = Color(red: 0x14 / 255, green: 0x3B / 255, blue: 0x1E / 255)
    static let accentFill = Color(red: 0xD9 / 255, green: 0xE6 / 255, blue: 0xD4 / 255)
}

/// Szklana karta na zielonym tle: jaśniejsza w lewym górnym rogu, z cienką jasną krawędzią.
struct OknaCard: ViewModifier {
    var padding = EdgeInsets(top: 24, leading: 26, bottom: 24, trailing: 26)
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                if reduceTransparency {
                    shape.fill(Color(red: 0.10, green: 0.27, blue: 0.14))
                } else {
                    shape.fill(LinearGradient(colors: [OknaTokens.cardTop, OknaTokens.cardBottom],
                                              startPoint: .topLeading, endPoint: UnitPoint(x: 1, y: 0.85)))
                }
            }
            .overlay { shape.strokeBorder(OknaTokens.cardBorder, lineWidth: 1).allowsHitTesting(false) }
    }
}

/// Przyciski strony Okna: jasny główny („Zobacz jak”) i półprzezroczysty drugorzędny.
struct OknaButtonStyle: ButtonStyle {
    var prominent = false
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        configuration.label
            .font(.body.weight(prominent ? .semibold : .regular))
            .foregroundStyle(prominent ? OknaTokens.accentText : OknaTokens.buttonText)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(minHeight: 36)
            .background {
                if prominent {
                    shape.fill(OknaTokens.accentFill.opacity(configuration.isPressed ? 0.8 : hovering ? 1 : 0.92))
                } else {
                    shape.fill(Color.white.opacity(configuration.isPressed ? 0.05 : hovering ? 0.14 : 0.09))
                }
            }
            .overlay { if !prominent { shape.strokeBorder(OknaTokens.cardBorder, lineWidth: 1) } }
            .contentShape(shape)
            .onHover { hovering = $0 }
    }
}

/// Nagłówek sekcji wielkimi literami, jak „JAK TO DZIAŁA”.
struct OknaSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(OknaTokens.mutedText)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Zielone tło zakładki Okna (to samo co `SeamBackdrop.IsGreen` na Windowsie). ContentView kładzie je
/// pod całe okno, razem z paskiem bocznym, tak jak SeamBackdrop pod pozostałe strony.
struct WindowsBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(stops: [.init(color: Color(red: 0x06 / 255, green: 0x4B / 255, blue: 0x1C / 255), location: 0),
                                   .init(color: Color(red: 0x02 / 255, green: 0x2F / 255, blue: 0x15 / 255), location: 0.78)],
                           startPoint: .topLeading, endPoint: UnitPoint(x: 1, y: 0.85))
            EllipticalGradient(colors: [Color(red: 0x55 / 255, green: 0x8B / 255, blue: 0x04 / 255).opacity(0.9), .clear],
                               center: UnitPoint(x: 0.54, y: -0.08), endRadiusFraction: 0.61)
            EllipticalGradient(colors: [Color(red: 0x00 / 255, green: 0x6F / 255, blue: 0x24 / 255).opacity(0.8), .clear],
                               center: UnitPoint(x: 0, y: 0.6), endRadiusFraction: 0.55)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
