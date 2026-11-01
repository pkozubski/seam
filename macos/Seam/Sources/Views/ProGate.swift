import SwiftUI

/// Plakietka „PRO” przy funkcjach płatnych.
struct ProBadge: View {
    var body: some View {
        Text(verbatim: "PRO")
            .font(.caption2.weight(.bold)).tracking(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(LinearGradient(colors: [Color(red: 0.98, green: 0.72, blue: 0.30), Color(red: 0.93, green: 0.42, blue: 0.47)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), in: Capsule())
            .accessibilityLabel(Text(L10n.text("Seam Pro feature", pl: "Funkcja Seam Pro")))
    }
}

/// Licznik trialu obok tytułu głównej karty („Trial · 5 days left”).
struct TrialPill: View {
    let daysLeft: Int
    var border: Color

    var body: some View {
        Text(verbatim: L10n.text(daysLeft == 1 ? "Trial · last day" : "Trial · \(daysLeft) days left",
                                 pl: daysLeft == 1 ? "Okres próbny · ostatni dzień" : "Okres próbny · zostało \(daysLeft) dni"))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 9).padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
    }
}

/// Karta pod głównym przełącznikiem funkcji Pro, gdy ani ten Mac, ani połączony PC nie ma Pro:
/// trial, zakup albo klucz. Na kolorowych stronach w ich kolorze.
struct ProGateCard: View {
    @Environment(AppState.self) private var state
    var border: Color
    var mutedText: Color

    private var license: LicenseManager { state.license }

    private var title: String {
        switch license.entitlement.state {
        case .trialExpired: return L10n.text("Your free trial has ended", pl: "Okres próbny się skończył")
        case .validationRequired: return L10n.text("Seam needs to check your license", pl: "Seam musi sprawdzić licencję")
        case .revoked: return L10n.text("Your license is no longer active", pl: "Licencja nie jest już aktywna")
        default: return L10n.text("Part of Seam Pro", pl: "Część Seam Pro")
        }
    }

    private var message: String {
        switch license.entitlement.state {
        case .trialExpired, .revoked:
            return L10n.text("Buy Seam Pro once and keep audio, windows and images in the clipboard. Keyboard, mouse and text stay free.",
                             pl: "Kup Seam Pro raz i zachowaj dźwięk, okna i obrazy w schowku. Klawiatura, mysz i tekst zostają darmowe.")
        case .validationRequired:
            return L10n.text("Connect this Mac to the internet for a moment. Seam checks the license at least once every 30 days.",
                             pl: "Połącz tego Maca na chwilę z internetem. Seam sprawdza licencję co najmniej raz na 30 dni.")
        default:
            return L10n.text("Try audio, windows and images in the clipboard free for \(Entitlement.trialDays) days. Keyboard, mouse and text stay free forever.",
                             pl: "Wypróbuj dźwięk, okna i obrazy w schowku za darmo przez \(Entitlement.trialDays) dni. Klawiatura, mysz i tekst są darmowe na zawsze.")
        }
    }

    @ViewBuilder private var actions: some View {
        if license.entitlement.state == .validationRequired {
            Button(L10n.text("Check now", pl: "Sprawdź teraz")) { Task { await license.revalidate() } }
                .buttonStyle(ProPrimaryButtonStyle())
                .disabled(license.isBusy)
        } else if license.canStartTrial {
            Button(L10n.text("Start \(Entitlement.trialDays)-day trial", pl: "Wypróbuj \(Entitlement.trialDays) dni")) { license.startTrial() }
                .buttonStyle(ProPrimaryButtonStyle())
            Button(L10n.text("Buy Pro – \(LicenseConfig.price)", pl: "Kup Pro – \(LicenseConfig.price)")) { license.openCheckout() }
                .buttonStyle(GlassPillButtonStyle(border: border)).fixedSize()
        } else {
            Button(L10n.text("Buy Pro – \(LicenseConfig.price)", pl: "Kup Pro – \(LicenseConfig.price)")) { license.openCheckout() }
                .buttonStyle(ProPrimaryButtonStyle())
        }
    }

    private var keyLink: some View {
        Button(L10n.text("Enter license key", pl: "Wpisz klucz licencji")) { SettingsNavigation.shared.present(.license) }
            .buttonStyle(.plain)
            .font(.callout.weight(.medium))
            .foregroundStyle(mutedText).fixedSize()
    }

    var body: some View {
        TintedGlassCard(border: border) {
            HStack(spacing: 10) {
                ProBadge()
                Text(verbatim: title).font(.headline)
            }
            Text(verbatim: message)
                .font(.callout).foregroundStyle(mutedText)
                .fixedSize(horizontal: false, vertical: true)
            // W wąskiej kolumnie (Schowek) link do klucza schodzi pod przyciski zamiast łamać ich tekst.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    actions
                    keyLink.padding(.leading, 4)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) { actions }
                    keyLink
                }
            }
        }
        .frame(maxWidth: 600)
    }
}

/// Główny przycisk karty Pro: biała pigułka z ciemnym tekstem, widoczna na każdym kolorze strony.
struct ProPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .lineLimit(1).fixedSize()
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(Color.white.opacity(configuration.isPressed ? 0.75 : 0.95), in: Capsule())
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Capsule())
    }
}
