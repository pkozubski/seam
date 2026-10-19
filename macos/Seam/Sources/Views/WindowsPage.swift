import SwiftUI

struct WindowsPage: View {
    @EnvironmentObject private var state: AppState
    var openConnection: () -> Void = {}
    var fullPreview = false
    @State private var width: CGFloat = 900

    private var edge: ScreenEdge { state.displayEdge ?? .right }

    var body: some View {
        Group {
            if fullPreview {
                guide.frame(width: 1020).padding(40)
            } else {
                scrollContent
            }
        }
        // W oknie aplikacji zielone tło leży pod całym oknem (ContentView), razem z szyną nawigacji.
        .background { if fullPreview { WindowsBackdrop().ignoresSafeArea() } }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private var scrollContent: some View {
        ScrollView {
            guide
                .frame(maxWidth: 1060, alignment: .leading)
                .padding(.horizontal, width < 850 ? 24 : 40)
                .padding(.top, 30)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity)
        }
    }

    /// Also used by the full-length preview without imposing a window-sized viewport.
    var guide: some View {
        VStack(alignment: .leading, spacing: 20) {
            WindowsGuideHeader(compact: width < 920).padding(.bottom, 8)
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
            WindowTransferDemo(edge: edge, macName: state.settings.deviceName,
                               peerName: state.peer?.name ?? L10n.text("Drugi komputer", "Other computer"),
                               isExample: state.displayEdge == nil)
            HStack(alignment: .top, spacing: 24) {
                WindowGuideStep(number: 1, title: L10n.text("Otwórz dowolne okno", "Open any window"),
                                detail: L10n.text("Przeglądarka, dokument, komunikator — to, z czym pracujesz.",
                                                  "A browser, document or chat — whatever you are working on."),
                                progress: 0, edge: edge)
                WindowGuideStep(number: 2, title: L10n.text("Przeciągnij za krawędź", "Drag across the edge"),
                                detail: L10n.text("Chwyć górny pasek i przesuń okno w stronę drugiego ekranu.",
                                                  "Grab the title bar and move it towards the other display."),
                                progress: 0.5, edge: edge)
                WindowGuideStep(number: 3, title: L10n.text("Pracuj na drugim ekranie", "Use the other display"),
                                detail: L10n.text("Okno pojawi się na drugim urządzeniu. Możesz pracować dalej.",
                                                  "Your window appears on the other device. Carry on working."),
                                progress: 1, edge: edge)
            }
            .modifier(WindowGuideSurface())
            WindowArrangementCard(edge: state.displayEdge)
            HStack(alignment: .top, spacing: 20) {
                WindowGuideNote(title: L10n.text("Dowolne okno", "Any window"),
                                detail: L10n.text("Przenosisz okna bezpośrednio z pulpitu, tak jak między dwoma monitorami.",
                                                  "Move windows directly from your desktop, just like between two monitors."),
                                symbol: "macwindow.on.rectangle", edge: edge, progress: 1)
                WindowGuideNote(title: L10n.text("Powrót na Maca", "Back to the Mac"),
                                detail: L10n.text("Przeciągnij okno przez wspólną krawędź w przeciwną stronę.",
                                                  "Drag the window back across the shared edge in the opposite direction."),
                                symbol: "arrow.uturn.backward", edge: edge, progress: 0)
            }
            HStack(alignment: .top) {
                Label(state.displayStreaming && state.settings.displayEnabled && state.screenCaptureGranted && state.accessibilityGranted
                      ? L10n.text("Drugi ekran jest gotowy.", "Your second display is ready.")
                      : L10n.text("Stan funkcji znajdziesz u góry strony.", "Check the feature status at the top of this page."),
                      systemImage: state.displayStreaming ? "checkmark.circle" : "info.circle")
                    .font(.callout).foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button(L10n.text("Szczegóły połączenia", "Connection details"), action: openConnection).buttonStyle(.link)
            }
            .padding(.horizontal, 8).padding(.top, 6)
        }
    }
}

/// Zielone tło zakładki Okna; ContentView kładzie je pod całe okno, tak jak SeamBackdrop pod pozostałe strony.
struct WindowsBackdrop: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.025, green: 0.16, blue: 0.17),
                                Color(red: 0.035, green: 0.12, blue: 0.14)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                EllipticalGradient(colors: [Color(red: 0.20, green: 0.45, blue: 0.36).opacity(0.6), .clear],
                                   center: .topTrailing, endRadiusFraction: 0.9)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
