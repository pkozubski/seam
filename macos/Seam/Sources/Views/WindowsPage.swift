import SwiftUI

/// Zakładka Okna: okno przechodzące przez świetlny szew, główny przełącznik i trzy kroki, na zielonym tle (`WindowsBackdrop`).
struct WindowsPage: View {
    @Environment(AppState.self) private var state
    var openConnection: () -> Void = {}
    var fullPreview = false

    private static let helpURL = URL(string: "https://github.com/pkozubski/seam#uruchomienie-krok-po-kroku")!

    private var status: String {
        if !state.proUnlocked { return L10n.text("Paused — needs Seam Pro", pl: "Wstrzymane – wymaga Seam Pro") }
        return state.settings.displayEnabled ? state.displayStatusText : L10n.text("Off", pl: "Wyłączone")
    }

    /// Uprawnienia są potrzebne tylko, gdy funkcja może działać.
    private var featureActive: Bool { state.settings.displayEnabled && state.proUnlocked }

    private var edgeText: String {
        switch state.displayEdge {
        case .left: return L10n.text("The Windows screen is to the left of the Mac", pl: "Ekran Windows stoi po lewej od Maca")
        case .right: return L10n.text("The Windows screen is to the right of the Mac", pl: "Ekran Windows stoi po prawej od Maca")
        case .top: return L10n.text("The Windows screen is above the Mac", pl: "Ekran Windows stoi nad Makiem")
        case .bottom: return L10n.text("The Windows screen is below the Mac", pl: "Ekran Windows stoi pod Makiem")
        case nil: return L10n.text("The screen layout appears when the second display starts",
                                   pl: "Układ ekranów pojawi się po uruchomieniu drugiego ekranu")
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
            Text(L10n.text("Your apps on both computers", pl: "Twoje aplikacje na obu komputerach"))
                .font(.system(size: 36, weight: .semibold)).tracking(-0.8)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if featureActive && !state.screenCaptureGranted {
                PermissionBanner(title: "Screen Recording permission missing",
                                 message: "Needed only for this feature. Relaunch the app after granting it.",
                                 grant: state.requestScreenCapture, openSettings: state.openScreenCaptureSettings)
            }
            if featureActive && !state.accessibilityGranted {
                PermissionBanner(title: "Accessibility permission missing",
                                 message: "Allows moving windows and controlling them on the other device.",
                                 grant: state.requestAccessibility, openSettings: state.openAccessibilitySettings)
            }
            TintedGlassCard(border: OknaTokens.cardBorder) {
                HStack(spacing: 14) {
                    SeamArtwork(name: "tile-windows-lime").frame(width: 46, height: 46)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(L10n.text("Window moving", pl: "Przenoszenie okien")).font(.title3.weight(.semibold))
                            if !state.proUnlocked { ProBadge() }
                            if let days = state.license.entitlement.trialDaysLeft { TrialPill(daysLeft: days, border: OknaTokens.cardBorder) }
                        }
                        HStack(spacing: 7) {
                            StatusDot(ok: state.displayStreaming ? true : (state.displayError == nil ? nil : false))
                            Text(status).font(.callout).foregroundStyle(OknaTokens.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    if state.displayStreaming {
                        Button(L10n.text("Stop", pl: "Zatrzymaj"), action: state.stopDisplay)
                            .buttonStyle(GlassPillButtonStyle(border: OknaTokens.cardBorder))
                    }
                    // Bez Pro przełącznik pokazuje „wyłączone”, ale zapisana wartość zostaje na po zakupie.
                    Toggle(L10n.text("Move windows", pl: "Przenoszenie okien"),
                           isOn: state.proUnlocked ? $state.settings.displayEnabled : .constant(false))
                        .labelsHidden().toggleStyle(.switch)
                        .disabled(!state.proUnlocked)
                }
            }
            .frame(maxWidth: 620)
            if !state.proUnlocked {
                ProGateCard(border: OknaTokens.cardBorder, mutedText: OknaTokens.mutedText)
            }
            steps(narrow: narrow)
            footer
        }
    }

    private func steps(narrow: Bool) -> some View {
        let items = [L10n.text("Open any window", pl: "Otwórz dowolne okno"),
                     L10n.text("Drag it across the screen edge", pl: "Przeciągnij je za krawędź ekranu"),
                     L10n.text("Work on the other computer", pl: "Pracuj na drugim komputerze")]
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
            Text(edgeText + L10n.text(" · change the layout, Windows apps on the Mac and full-desktop mode in Seam on Windows.",
                                      pl: " · układ, okna Windows na Macu i tryb całego pulpitu zmienisz w Seam na Windowsie."))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if state.peer == nil {
                HStack(spacing: 18) {
                    Button(L10n.text("Connection settings", pl: "Ustawienia połączenia"), action: openConnection)
                        .buttonStyle(.link)
                    Link(destination: Self.helpURL) {
                        HStack(spacing: 5) {
                            Text(L10n.text("Connection help", pl: "Pomoc z połączeniem"))
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
