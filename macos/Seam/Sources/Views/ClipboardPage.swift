import SwiftUI

/// Schowek: szklany schowek po lewej, karty ustawień po prawej, na bursztynowym tle (`ClipboardBackdrop`).
struct ClipboardPage: View {
    @Environment(AppState.self) private var state

    private var status: String {
        state.settings.clipboardSyncEnabled ? state.clipboardStatus : L10n.text("Off", pl: "Wyłączone")
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                HStack(alignment: .center, spacing: 20) {
                    VStack(spacing: 14) {
                        ClipboardHero()
                            .frame(maxWidth: 500)
                            .background {
                                Ellipse()
                                    .fill(ClipboardTokens.glow.opacity(0.5))
                                    .padding(.horizontal, 40).padding(.vertical, 60)
                                    .blur(radius: 70)
                                    .allowsHitTesting(false)
                            }
                        Text(L10n.text("Copy on the Mac, paste on Windows.", pl: "Kopiuj na Macu, wklejaj na Windowsie."))
                            .font(.title3).foregroundStyle(ClipboardTokens.mutedText.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity)
                    settings
                        .frame(width: geometry.size.width < 860 ? 340 : 420)
                }
                .padding(.horizontal, 28).padding(.top, 30).padding(.bottom, 90)
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: 1180)
                .frame(maxWidth: .infinity)
            }
        }
        .tint(ClipboardTokens.accent)
    }

    private var settings: some View {
        @Bindable var state = state
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("Clipboard", pl: "Schowek"))
                    .font(.system(size: 40, weight: .semibold)).tracking(-1)
                    .accessibilityAddTraits(.isHeader)
                Text(L10n.text("Copy on one computer, paste on the other.", pl: "Kopiuj na jednym komputerze, wklejaj na drugim."))
                    .font(.system(size: 16)).foregroundStyle(ClipboardTokens.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 10)
            TintedGlassCard(border: ClipboardTokens.cardBorder) {
                HStack(spacing: 14) {
                    SeamArtwork(name: "tile-clipboard-amber").frame(width: 46, height: 46)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("Sync clipboard", pl: "Synchronizuj schowek")).font(.title3.weight(.semibold))
                        HStack(spacing: 7) {
                            StatusDot(ok: state.settings.clipboardSyncEnabled ? (state.peer != nil ? true : nil) : nil)
                            Text(status).font(.callout).foregroundStyle(ClipboardTokens.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    Toggle(L10n.text("Sync clipboard", pl: "Synchronizuj schowek"), isOn: $state.settings.clipboardSyncEnabled)
                        .labelsHidden().toggleStyle(.switch)
                }
            }
            TintedGlassCard(border: ClipboardTokens.cardBorder) {
                Text(L10n.text("What is sent", pl: "Co jest przesyłane")).font(.title3.weight(.semibold))
                VStack(spacing: 0) {
                    // Tekst jest darmowy, obrazy to Seam Pro.
                    let items = [("textformat", L10n.text("Text", pl: "Tekst"), false),
                                 ("photo", L10n.text("Photos and screenshots", pl: "Zdjęcia i zrzuty ekranu"), true),
                                 ("doc.richtext", L10n.text("Images up to 32 MiB", pl: "Obrazy do 32 MiB"), true)]
                    ForEach(items.indices, id: \.self) { index in
                        if index > 0 { Divider().overlay(ClipboardTokens.cardBorder).padding(.leading, 50) }
                        HStack(spacing: 14) {
                            ClipboardTypeIcon(symbol: items[index].0)
                            Text(items[index].1).font(.body)
                            Spacer(minLength: 0)
                            if items[index].2 && !state.proUnlocked { ProBadge() }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            if !state.proUnlocked {
                ProGateCard(border: ClipboardTokens.cardBorder, mutedText: ClipboardTokens.mutedText)
            }
            TintedGlassCard(border: ClipboardTokens.cardBorder) {
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 18)).foregroundStyle(ClipboardTokens.light)
                        .accessibilityHidden(true)
                    Text(L10n.text("Both ways, on the local network only, encrypted like the whole connection.",
                                   pl: "W obie strony, tylko w sieci lokalnej, szyfrowane jak całe połączenie."))
                        .font(.callout).foregroundStyle(ClipboardTokens.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
