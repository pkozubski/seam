import SwiftUI

/// Klawiatura i mysz: grafika po lewej, szklane karty ustawień po prawej, na magentowym tle (`ControlBackdrop`).
struct InputPage: View {
    @Environment(AppState.self) private var state

    private var status: String {
        guard state.settings.inputEnabled else { return L10n.text("Wyłączone", "Off") }
        guard state.peer != nil else { return L10n.text("Czeka na połączenie z Windowsem", "Waiting for Windows") }
        return state.cursorOnMac
            ? L10n.text("Aktywne · kursor jest na Macu", "Active · the pointer is on the Mac")
            : L10n.text("Aktywne · kursor jest na Windowsie", "Active · the pointer is on Windows")
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
                        Text(L10n.text("Kursor przechodzi przez krawędź ekranu.", "The pointer crosses the screen edge."))
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
                Text(L10n.text("Klawiatura i mysz", "Keyboard & mouse"))
                    .font(.system(size: 40, weight: .semibold)).tracking(-1)
                    .accessibilityAddTraits(.isHeader)
                Text(L10n.text("Jedna klawiatura i mysz dla obu komputerów.", "One keyboard and mouse for both computers."))
                    .font(.system(size: 16)).foregroundStyle(ControlTokens.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 10)
            if !state.accessibilityGranted {
                PermissionBanner(title: "Brak uprawnienia Dostępność",
                                 message: "Bez niego Mac nie przyjmie ruchów myszy ani klawiszy z Windowsa.",
                                 grant: state.requestAccessibility,
                                 openSettings: state.openAccessibilitySettings)
            }
            TintedGlassCard {
                HStack(spacing: 14) {
                    SeamArtwork(name: "tile-input").frame(width: 46, height: 46)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("Sterowanie z Windowsa", "Control from Windows")).font(.title3.weight(.semibold))
                        HStack(spacing: 7) {
                            StatusDot(ok: state.settings.inputEnabled ? (state.peer != nil ? true : nil) : nil)
                            Text(status).font(.callout).foregroundStyle(ControlTokens.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    Toggle(L10n.text("Sterowanie z Windowsa", "Control from Windows"), isOn: $state.settings.inputEnabled)
                        .labelsHidden().toggleStyle(.switch)
                }
            }
            TintedGlassCard {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("Zamień Ctrl ↔ Cmd", "Swap Ctrl ↔ Cmd")).font(.title3.weight(.semibold))
                        Text(L10n.text("Ctrl+C na PC działa jak ⌘C.", "Ctrl+C on the PC works like ⌘C."))
                            .font(.callout).foregroundStyle(ControlTokens.mutedText)
                    }
                    Spacer(minLength: 8)
                    Toggle(L10n.text("Zamień Ctrl ↔ Cmd", "Swap Ctrl ↔ Cmd"), isOn: $state.settings.swapCtrlCmd)
                        .labelsHidden().toggleStyle(.switch)
                }
            }
            TintedGlassCard {
                Text(L10n.text("Przewijanie", "Scrolling")).font(.title3.weight(.semibold))
                Picker(L10n.text("Kierunek", "Direction"), selection: $state.settings.scrollDirection) {
                    ForEach(ScrollDirectionMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help(L10n.text("„Automatycznie” uwzględnia naturalne przewijanie z ustawień Maca.",
                                "“Automatic” follows natural scrolling from the Mac's settings."))
                Divider().overlay(ControlTokens.cardBorder)
                HStack(spacing: 12) {
                    Text(L10n.text("Szybkość", "Speed")).font(.body.weight(.semibold))
                    Text("\(state.settings.scrollSpeed.formatted(.number.precision(.fractionLength(0...2))))×")
                        .font(.body.monospacedDigit()).foregroundStyle(ControlTokens.mutedText)
                    Slider(value: $state.settings.scrollSpeed, in: 0.25...4, step: 0.25) {
                        Text(L10n.text("Szybkość", "Speed"))
                    } minimumValueLabel: {
                        Image(systemName: "tortoise").accessibilityHidden(true)
                    } maximumValueLabel: {
                        Image(systemName: "hare").accessibilityHidden(true)
                    }
                    .labelsHidden()
                }
                .help("\(Int(40 * state.settings.scrollSpeed)) px" + L10n.text(" na ząbek kółka", " per wheel notch"))
            }
            Text(L10n.text("Skrót awaryjny, czułość myszy i położenie ekranów ustawiasz w aplikacji na Windowsie.",
                           "Set the emergency shortcut, mouse sensitivity and screen layout in the Windows app."))
                .font(.callout).foregroundStyle(ControlTokens.mutedText.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 4)
        }
    }
}
