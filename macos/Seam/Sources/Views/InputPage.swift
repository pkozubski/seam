import SwiftUI

/// Klawiatura i mysz: grafika po lewej, szklane karty ustawień po prawej, na magentowym tle (`ControlBackdrop`).
struct InputPage: View {
    @Environment(AppState.self) private var state

    private var status: String {
        guard state.settings.inputEnabled else { return L10n.text("Off", pl: "Wyłączone") }
        guard state.peer != nil else { return L10n.text("Waiting for Windows", pl: "Czeka na połączenie z Windowsem") }
        return state.cursorOnMac
            ? L10n.text("Active · the pointer is on the Mac", pl: "Aktywne · kursor jest na Macu")
            : L10n.text("Active · the pointer is on Windows", pl: "Aktywne · kursor jest na Windowsie")
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                HStack(alignment: .center, spacing: 20) {
                    VStack(spacing: 14) {
                        // Mysz i klawisz ⌘ to osobne grafiki; klawisz stoi przed myszą, w lewym dolnym rogu.
                        ZStack(alignment: .bottomLeading) {
                            SeamArtwork(name: "hero-control-mouse")
                                .padding(.leading, 70).padding(.bottom, 20)
                            SeamArtwork(name: "hero-control-key")
                                .frame(width: 170)
                                .shadow(color: ControlTokens.hotGlow.opacity(0.35), radius: 24)
                        }
                        .frame(maxWidth: 500)
                        .background {
                            // Szeroka poświata pod grafiką, jak na makiecie; wychodzi poza ramkę grafiki.
                            Ellipse()
                                .fill(ControlTokens.hotGlow.opacity(0.5))
                                .padding(.horizontal, 30).padding(.vertical, 50)
                                .blur(radius: 70)
                                .allowsHitTesting(false)
                        }
                        Text(L10n.text("The pointer crosses the screen edge.", pl: "Kursor przechodzi przez krawędź ekranu."))
                            .font(.callout).foregroundStyle(ControlTokens.mutedText.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    settings
                        .frame(width: geometry.size.width < 860 ? 340 : 420)
                }
                .padding(.horizontal, 28).padding(.top, 30).padding(.bottom, 90)
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: 1180)
                .frame(maxWidth: .infinity)
            }
        }
        .tint(ControlTokens.accent)
    }

    private var settings: some View {
        @Bindable var state = state
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("Keyboard & mouse", pl: "Klawiatura i mysz"))
                    .font(.system(size: 40, weight: .semibold)).tracking(-1)
                    .accessibilityAddTraits(.isHeader)
                Text(L10n.text("One keyboard and mouse for both computers.", pl: "Jedna klawiatura i mysz dla obu komputerów."))
                    .font(.system(size: 16)).foregroundStyle(ControlTokens.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 10)
            if !state.accessibilityGranted {
                PermissionBanner(title: "Accessibility permission missing",
                                 message: "Without it the Mac cannot accept mouse and key input from Windows.",
                                 grant: state.requestAccessibility,
                                 openSettings: state.openAccessibilitySettings)
            }
            TintedGlassCard {
                HStack(spacing: 14) {
                    SeamArtwork(name: "tile-input").frame(width: 46, height: 46)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("Control from Windows", pl: "Sterowanie z Windowsa")).font(.title3.weight(.semibold))
                        HStack(spacing: 7) {
                            StatusDot(ok: state.settings.inputEnabled ? (state.peer != nil ? true : nil) : nil)
                            Text(status).font(.callout).foregroundStyle(ControlTokens.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    Toggle(L10n.text("Control from Windows", pl: "Sterowanie z Windowsa"), isOn: $state.settings.inputEnabled)
                        .labelsHidden().toggleStyle(.switch)
                }
            }
            TintedGlassCard {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("Swap Ctrl ↔ Cmd", pl: "Zamień Ctrl ↔ Cmd")).font(.title3.weight(.semibold))
                        Text(L10n.text("Ctrl+C on the PC works like ⌘C.", pl: "Ctrl+C na PC działa jak ⌘C."))
                            .font(.callout).foregroundStyle(ControlTokens.mutedText)
                    }
                    Spacer(minLength: 8)
                    Toggle(L10n.text("Swap Ctrl ↔ Cmd", pl: "Zamień Ctrl ↔ Cmd"), isOn: $state.settings.swapCtrlCmd)
                        .labelsHidden().toggleStyle(.switch)
                }
            }
            TintedGlassCard {
                Text(L10n.text("Scrolling", pl: "Przewijanie")).font(.title3.weight(.semibold))
                Picker(L10n.text("Direction", pl: "Kierunek"), selection: $state.settings.scrollDirection) {
                    ForEach(ScrollDirectionMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help(L10n.text("“Automatic” follows natural scrolling from the Mac's settings.",
                                pl: "„Automatycznie” uwzględnia naturalne przewijanie z ustawień Maca."))
                Divider().overlay(ControlTokens.cardBorder)
                HStack(spacing: 12) {
                    Text(L10n.text("Speed", pl: "Szybkość")).font(.body.weight(.semibold))
                    Text("\(state.settings.scrollSpeed.formatted(.number.precision(.fractionLength(0...2))))×")
                        .font(.body.monospacedDigit()).foregroundStyle(ControlTokens.mutedText)
                    Slider(value: $state.settings.scrollSpeed, in: 0.25...4, step: 0.25) {
                        Text(L10n.text("Speed", pl: "Szybkość"))
                    } minimumValueLabel: {
                        Image(systemName: "tortoise").accessibilityHidden(true)
                    } maximumValueLabel: {
                        Image(systemName: "hare").accessibilityHidden(true)
                    }
                    .labelsHidden()
                }
                .help("\(Int(40 * state.settings.scrollSpeed)) px" + L10n.text(" per wheel notch", pl: " na ząbek kółka"))
            }
            Text(L10n.text("Set the emergency shortcut, mouse sensitivity and screen layout in the Windows app.",
                           pl: "Skrót awaryjny, czułość myszy i położenie ekranów ustawiasz w aplikacji na Windowsie."))
                .font(.callout).foregroundStyle(ControlTokens.mutedText.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 4)
        }
    }
}
