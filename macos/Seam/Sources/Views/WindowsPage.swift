import SwiftUI

/// Zakładka Okna w układzie z Windowsa (`windows/Seam/Views/Pages/WindowsPage.axaml`): główny przełącznik
/// w pigułce, ilustracja po lewej, połączenie i układ ekranów po prawej, szczegóły pod przewinięciem.
struct WindowsPage: View {
    @Environment(AppState.self) private var state
    var openConnection: () -> Void = {}
    var fullPreview = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 900

    private static let helpURL = URL(string: "https://github.com/pkozubski/seam#uruchomienie-krok-po-kroku")!
    private static let howID = "how"

    var body: some View {
        Group {
            if fullPreview {
                guide(scrollToHow: {}).frame(width: 1040).padding(40)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        guide(scrollToHow: {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) {
                                proxy.scrollTo(Self.howID, anchor: .top)
                            }
                        })
                        .frame(maxWidth: 1040)
                        .padding(.horizontal, width < 850 ? 24 : 40)
                        .padding(.top, 20)
                        .padding(.bottom, 48)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        // W oknie aplikacji zielone tło leży pod całym oknem (ContentView), razem z paskiem bocznym.
        .background { if fullPreview { WindowsBackdrop().ignoresSafeArea() } }
        .tint(OknaTokens.switchOn)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    /// Also used by the full-length preview without imposing a window-sized viewport.
    func guide(scrollToHow: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            header
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
            cards(scrollToHow: scrollToHow)
            HStack {
                Spacer()
                Link(destination: Self.helpURL) {
                    HStack(spacing: 6) {
                        Text(L10n.text("Pomoc z połączeniem", "Connection help"))
                        Image(systemName: "arrow.up.right.square").font(.system(size: 11))
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(OknaTokens.buttonText)
                }
                .padding(.horizontal, 6)
            }
            .padding(.top, -8)
            WindowsHowItWorks(edge: state.displayEdge ?? .right).id(Self.howID)
            WindowsDisplayOptions()
        }
    }

    private var header: some View {
        @Bindable var state = state
        return VStack(spacing: 16) {
            Text(L10n.text("Twoje aplikacje na obu komputerach.", "Your apps, on both computers."))
                .font(.system(size: 32, weight: .semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 18) {
                Text(state.settings.displayEnabled ? L10n.text("Przenoszenie okien włączone", "Window moving is on")
                                                   : L10n.text("Przenoszenie okien wyłączone", "Window moving is off"))
                    .font(.system(size: 15, weight: .semibold))
                Toggle(L10n.text("Przenoszenie okien", "Move windows"), isOn: $state.settings.displayEnabled)
                    .toggleStyle(.switch).labelsHidden()
            }
            .padding(.leading, 18).padding(.trailing, 10).padding(.vertical, 10)
            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(OknaTokens.cardBorder, lineWidth: 1) }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10).padding(.bottom, 6)
    }

    /// Siatka 5:9 jak na Windowsie; w wąskim oknie karty układają się jedna pod drugą.
    @ViewBuilder private func cards(scrollToHow: @escaping () -> Void) -> some View {
        let right = VStack(spacing: 18) {
            WindowsConnectionCard(openConnection: openConnection)
            WindowsArrangementCard(edge: state.displayEdge)
        }
        if width < 700 && !fullPreview {
            VStack(spacing: 18) {
                WindowsMoveCard(showHow: scrollToHow)
                right
            }
        } else {
            Grid(horizontalSpacing: 18) {
                GridRow {
                    WindowsMoveCard(showHow: scrollToHow).gridCellColumns(5)
                    right.gridCellColumns(9)
                }
                // Niewidoczny wiersz dzieli szerokość na 14 równych kolumn (proporcja 5:9).
                GridRow { ForEach(0..<14, id: \.self) { _ in Color.clear.frame(height: 0) } }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// „Jak to działa”: trzy etapy przeniesienia okna na schemacie ekranów.
private struct WindowsHowItWorks: View {
    let edge: ScreenEdge

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OknaSectionHeader(title: L10n.text("Jak to działa", "How it works"))
            HStack(alignment: .top, spacing: 18) {
                step(1, progress: 0, title: L10n.text("Otwórz dowolne okno", "Open any window"),
                     detail: L10n.text("Przeglądarka, dokument, komunikator — to, z czym pracujesz.",
                                       "A browser, document or chat — whatever you are working on."))
                step(2, progress: 0.5, title: L10n.text("Przeciągnij za krawędź", "Drag across the edge"),
                     detail: L10n.text("Chwyć górny pasek i przesuń okno w stronę drugiego ekranu.",
                                       "Grab the title bar and move it towards the other display."))
                step(3, progress: 1, title: L10n.text("Pracuj na drugim ekranie", "Use the other display"),
                     detail: L10n.text("Okno pojawi się na drugim urządzeniu. Wróci tą samą krawędzią w przeciwną stronę.",
                                       "Your window appears on the other device. It comes back across the same edge."))
            }
        }
        .modifier(OknaCard(padding: EdgeInsets(top: 20, leading: 22, bottom: 22, trailing: 22)))
    }

    private func step(_ number: Int, progress: CGFloat, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WindowTransferDiagram(edge: edge, progress: progress, compact: true).frame(height: 86)
            Text(String(format: "%02d", number))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(OknaTokens.stepNumber)
            Text(title).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Text(detail).font(.callout).foregroundStyle(OknaTokens.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

/// „Opcje wyświetlania” po stronie Maca: stan ekranu, który Mac udostępnia Windowsowi.
/// Kierunki i tryb pulpitu należą do aplikacji Windows, więc tu jest tylko wskazówka.
private struct WindowsDisplayOptions: View {
    @Environment(AppState.self) private var state

    private var statusColor: Color {
        if state.displayStreaming { return Color(red: 0.20, green: 0.78, blue: 0.35) }
        return state.displayError != nil ? .orange : .gray
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OknaSectionHeader(title: L10n.text("Opcje wyświetlania", "Display options"))
            HStack(spacing: 14) {
                SeamIconTile(name: "icon-windows", size: 34, active: state.displayStreaming)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("Okna Maca na komputerze z Windows", "Mac windows on your Windows computer"))
                    HStack(spacing: 7) {
                        Circle().fill(statusColor).frame(width: 7, height: 7).accessibilityHidden(true)
                        Text(state.displayStatusText).font(.callout).foregroundStyle(OknaTokens.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                if state.displayStreaming {
                    Button(L10n.text("Zatrzymaj", "Stop"), action: state.stopDisplay)
                        .buttonStyle(OknaButtonStyle())
                }
            }
            .frame(minHeight: 44)
            Rectangle().fill(OknaTokens.divider).frame(height: 1)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "pc").foregroundStyle(OknaTokens.mutedText).accessibilityHidden(true)
                Text(L10n.text("Okna Windows na Macu, tryb całego pulpitu i ponowne uruchomienie obrazu ustawisz w Seam na Windowsie, w zakładce Okna.",
                               "Windows apps on the Mac, full-desktop mode and restarting the stream are in Seam on Windows, under Windows."))
                    .font(.callout).foregroundStyle(OknaTokens.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .modifier(OknaCard(padding: EdgeInsets(top: 20, leading: 22, bottom: 20, trailing: 22)))
    }
}
