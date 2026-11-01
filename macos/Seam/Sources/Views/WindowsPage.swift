import SwiftUI

/// Zakładka Okna: okno przechodzące przez świetlny szew, główny przełącznik i trzy kroki, na zielonym tle (`WindowsBackdrop`).
struct WindowsPage: View {
    @Environment(AppState.self) private var state
    var openConnection: () -> Void = {}
    var fullPreview = false

    private static let helpURL = URL(string: "https://github.com/pkozubski/seam#uruchomienie-krok-po-kroku")!

    private var status: String {
        state.settings.displayEnabled ? state.displayStatusText : L10n.text("Wyłączone", "Off")
    }

    private var edgeText: String {
        switch state.displayEdge {
        case .left: return L10n.text("Ekran Windows stoi po lewej od Maca", "The Windows screen is to the left of the Mac")
        case .right: return L10n.text("Ekran Windows stoi po prawej od Maca", "The Windows screen is to the right of the Mac")
        case .top: return L10n.text("Ekran Windows stoi nad Makiem", "The Windows screen is above the Mac")
        case .bottom: return L10n.text("Ekran Windows stoi pod Makiem", "The Windows screen is below the Mac")
        case nil: return L10n.text("Układ ekranów pojawi się po uruchomieniu drugiego ekranu",
                                   "The screen layout appears when the second display starts")
        }
    }

    var body: some View {
        Group {
            if fullPreview {
                content(narrow: false, heroWidth: 820).frame(width: 1040).padding(40)
            } else {
                GeometryReader { geometry in
                    ScrollView {
                        content(narrow: geometry.size.width < 720, heroWidth: geometry.size.height < 760 ? 640 : 820)
                            .padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 96)
                            .frame(maxWidth: 1000)
                            .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    }
                }
            }
        }
        // W oknie aplikacji zielone tło leży pod całym oknem (ContentView), razem z paskiem bocznym.
        .background { if fullPreview { WindowsBackdrop().ignoresSafeArea() } }
        .tint(OknaTokens.accent)
    }

    private func content(narrow: Bool, heroWidth: CGFloat) -> some View {
        @Bindable var state = state
        return VStack(spacing: 22) {
            WindowsHero().frame(maxWidth: heroWidth)
            Text(L10n.text("Twoje aplikacje na obu komputerach", "Your apps on both computers"))
                .font(.system(size: 36, weight: .semibold)).tracking(-0.8)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if state.settings.displayEnabled && !state.screenCaptureGranted {
                PermissionBanner(title: "Brak uprawnienia Nagrywanie ekranu",
                                 message: "Potrzebne tylko tej funkcji. Po nadaniu uruchom aplikację ponownie.",
                                 grant: state.requestScreenCapture, openSettings: state.openScreenCaptureSettings)
            }
            if state.settings.displayEnabled && !state.accessibilityGranted {
                PermissionBanner(title: "Brak uprawnienia Dostępność",
                                 message: "Pozwala przenosić okna i sterować nimi na drugim urządzeniu.",
                                 grant: state.requestAccessibility, openSettings: state.openAccessibilitySettings)
            }
            TintedGlassCard(border: OknaTokens.cardBorder) {
                HStack(spacing: 14) {
                    SeamArtwork(name: "tile-windows-lime").frame(width: 46, height: 46)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("Przenoszenie okien", "Window moving")).font(.title3.weight(.semibold))
                        HStack(spacing: 7) {
                            StatusDot(ok: state.displayStreaming ? true : (state.displayError == nil ? nil : false))
                            Text(status).font(.callout).foregroundStyle(OknaTokens.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    if state.displayStreaming {
                        Button(L10n.text("Zatrzymaj", "Stop"), action: state.stopDisplay)
                            .buttonStyle(GlassPillButtonStyle(border: OknaTokens.cardBorder))
                    }
                    Toggle(L10n.text("Przenoszenie okien", "Move windows"), isOn: $state.settings.displayEnabled)
                        .labelsHidden().toggleStyle(.switch)
                }
            }
            .frame(maxWidth: 620)
            steps(narrow: narrow)
            footer
        }
    }

    private func steps(narrow: Bool) -> some View {
        let items = [L10n.text("Otwórz dowolne okno", "Open any window"),
                     L10n.text("Przeciągnij je za krawędź ekranu", "Drag it across the screen edge"),
                     L10n.text("Pracuj na drugim komputerze", "Work on the other computer")]
        let layout = narrow ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                            : AnyLayout(HStackLayout(spacing: 18))
        return TintedGlassCard(border: OknaTokens.cardBorder) {
            layout {
                ForEach(items.indices, id: \.self) { index in
                    if index > 0 && !narrow {
                        Rectangle().fill(OknaTokens.cardBorder).frame(width: 1, height: 52)
                    }
                    HStack(spacing: 16) {
                        OknaStepNumber(number: index + 1)
                        Text(items[index]).font(.body.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(index + 1). \(items[index])")
                }
            }
            .padding(.vertical, 6)
        }
    }

    /// Układ ekranów i ustawienia, które są tylko na Windowsie; bez połączenia także droga do jego ustawień.
    private var footer: some View {
        VStack(spacing: 8) {
            Text(edgeText + L10n.text(" · układ, okna Windows na Macu i tryb całego pulpitu zmienisz w Seam na Windowsie.",
                                      " · change the layout, Windows apps on the Mac and full-desktop mode in Seam on Windows."))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if state.peer == nil {
                HStack(spacing: 18) {
                    Button(L10n.text("Ustawienia połączenia", "Connection settings"), action: openConnection)
                        .buttonStyle(.link)
                    Link(destination: Self.helpURL) {
                        HStack(spacing: 5) {
                            Text(L10n.text("Pomoc z połączeniem", "Connection help"))
                            Image(systemName: "arrow.up.right.square").font(.system(size: 11))
                        }
                    }
                }
                .foregroundStyle(OknaTokens.light)
            }
        }
        .font(.callout).foregroundStyle(OknaTokens.mutedText)
        .padding(.top, 4)
    }
}
