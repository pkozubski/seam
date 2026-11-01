import SwiftUI

/// Schowek: szklany schowek po lewej, karty ustawień po prawej, na bursztynowym tle (`ClipboardBackdrop`).
struct ClipboardPage: View {
    @Environment(AppState.self) private var state

    private var status: String {
        state.settings.clipboardSyncEnabled ? state.clipboardStatus : L10n.text("Wyłączone", "Off")
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
                        Text(L10n.text("Kopiuj na Macu, wklejaj na Windowsie.", "Copy on the Mac, paste on Windows."))
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
                Text(L10n.text("Schowek", "Clipboard"))
                    .font(.system(size: 40, weight: .semibold)).tracking(-1)
                    .accessibilityAddTraits(.isHeader)
                Text(L10n.text("Kopiuj na jednym komputerze, wklejaj na drugim.", "Copy on one computer, paste on the other."))
                    .font(.system(size: 16)).foregroundStyle(ClipboardTokens.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 10)
            TintedGlassCard(border: ClipboardTokens.cardBorder) {
                HStack(spacing: 14) {
                    SeamArtwork(name: "tile-clipboard-amber").frame(width: 46, height: 46)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("Synchronizuj schowek", "Sync clipboard")).font(.title3.weight(.semibold))
                        HStack(spacing: 7) {
                            StatusDot(ok: state.settings.clipboardSyncEnabled ? (state.peer != nil ? true : nil) : nil)
                            Text(status).font(.callout).foregroundStyle(ClipboardTokens.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    Toggle(L10n.text("Synchronizuj schowek", "Sync clipboard"), isOn: $state.settings.clipboardSyncEnabled)
                        .labelsHidden().toggleStyle(.switch)
                }
            }
            TintedGlassCard(border: ClipboardTokens.cardBorder) {
                Text(L10n.text("Co jest przesyłane", "What is sent")).font(.title3.weight(.semibold))
                VStack(spacing: 0) {
                    let items = [("textformat", L10n.text("Tekst", "Text")),
                                 ("photo", L10n.text("Zdjęcia i zrzuty ekranu", "Photos and screenshots")),
                                 ("doc.richtext", L10n.text("Obrazy do 32 MiB", "Images up to 32 MiB"))]
                    ForEach(items.indices, id: \.self) { index in
                        if index > 0 { Divider().overlay(ClipboardTokens.cardBorder).padding(.leading, 50) }
                        HStack(spacing: 14) {
                            ClipboardTypeIcon(symbol: items[index].0)
                            Text(items[index].1).font(.body)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            TintedGlassCard(border: ClipboardTokens.cardBorder) {
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 18)).foregroundStyle(ClipboardTokens.light)
                        .accessibilityHidden(true)
                    Text(L10n.text("W obie strony, tylko w sieci lokalnej, szyfrowane jak całe połączenie.",
                                   "Both ways, on the local network only, encrypted like the whole connection."))
                        .font(.callout).foregroundStyle(ClipboardTokens.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
