import SwiftUI

/// Kula stanu połączenia: świecące szkło z białym symbolem, jak główny przycisk strony.
struct ConnectionStatusButton: View {
    /// Kolor połączonej kuli: strony z własnym kolorem (Klawiatura i mysz, Dźwięk, Schowek, Okna) dostają swój, reszta niebieski.
    enum Accent { case blue, magenta, violet, amber, leaf }

    let state: AppState
    var accent: Accent = .blue
    let action: () -> Void
    @State private var hovering = false

    static let orbSize: CGFloat = 98
    /// Margines panelu na poświatę; poświata musi zgasnąć przed krawędzią panelu, bo inaczej widać kwadrat.
    static let glowInset: CGFloat = 46
    static let panelSide = orbSize + glowInset * 2

    private var connected: Bool { state.peer != nil && state.listenError == nil }

    /// Jasny refleks, środek i ciemna krawędź szkła.
    private var palette: (light: Color, mid: Color, deep: Color, glow: Color) {
        if state.listenError != nil {
            return (Color(red: 1, green: 0.78, blue: 0.45), .orange, Color(red: 0.45, green: 0.18, blue: 0.02), .orange)
        }
        if connected {
            switch accent {
            case .blue:
                return (ConnectionTokens.cyanGlow, ConnectionTokens.cobaltGlow, ConnectionTokens.deepTop, ConnectionTokens.cyanGlow)
            case .magenta:
                return (Color(red: 1, green: 0.55, blue: 0.82), ControlTokens.accent, ControlTokens.center, ControlTokens.hotGlow)
            case .violet:
                return (AudioTokens.barLight, AudioTokens.accent, AudioTokens.top, AudioTokens.accent)
            case .amber:
                return (ClipboardTokens.light, ClipboardTokens.accent, ClipboardTokens.center, ClipboardTokens.glow)
            case .leaf:
                return (OknaTokens.light, OknaTokens.accent, OknaTokens.center, OknaTokens.glow)
            }
        }
        return (Color(white: 0.62), Color(white: 0.3), Color(white: 0.1), .clear)
    }

    private var label: String {
        if state.listenError != nil { return L10n.text("Błąd", "Error") }
        return connected ? L10n.text("Połączono", "Connected") : L10n.text("Oczekiwanie", "Waiting")
    }

    private var symbol: String {
        if state.listenError != nil { return "exclamationmark.triangle.fill" }
        return connected ? "link" : "antenna.radiowaves.left.and.right"
    }

    var body: some View {
        let colors = palette
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .accessibilityHidden(true)
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .shadow(color: colors.deep.opacity(0.6), radius: 2, y: 1)
            .frame(width: Self.orbSize, height: Self.orbSize)
            .background {
                ZStack {
                    Circle().fill(RadialGradient(colors: [colors.light, colors.mid, colors.deep],
                                                 center: UnitPoint(x: 0.38, y: 0.22),
                                                 startRadius: 2, endRadius: Self.orbSize * 0.78))
                    // Szklany refleks u góry.
                    Ellipse()
                        .fill(LinearGradient(colors: [.white.opacity(0.26), .white.opacity(0)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: Self.orbSize * 0.7, height: Self.orbSize * 0.42)
                        .offset(y: -Self.orbSize * 0.24)
                    Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.75), colors.light.opacity(0.25), .white.opacity(0.35)],
                                                         startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
                }
                .brightness(hovering ? 0.06 : 0)
            }
            .background {
                // Poświata: rozmyte koło mieści się w `glowInset`, więc nie ucina jej krawędź panelu.
                Circle()
                    .fill(colors.glow)
                    .frame(width: Self.orbSize, height: Self.orbSize)
                    .blur(radius: 16)
                    .opacity(hovering ? 0.95 : 0.75)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(L10n.text("Stan i szczegóły połączenia", "Connection status and details"))
        .accessibilityLabel(state.statusSummary.text)
        .accessibilityHint(L10n.text("Otwiera szczegóły połączenia", "Opens connection details"))
        .frame(width: Self.panelSide, height: Self.panelSide)
        .preferredColorScheme(.dark)
    }
}
