import SwiftUI

/// Tytuł i opis karty strony Okna.
private struct OknaCardHeading: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 20, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(detail).font(.system(size: 14.5)).lineSpacing(4)
                .foregroundStyle(OknaTokens.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// „Przenieś dowolne okno”: ilustracja i przycisk, który przewija do sekcji „Jak to działa”.
struct WindowsMoveCard: View {
    let showHow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OknaCardHeading(title: L10n.text("Przenieś dowolne okno", "Move any window"),
                            detail: L10n.text("Przeciągnij aplikację do krawędzi ekranu. Pojawi się na drugim komputerze.",
                                              "Drag an app to the edge of the screen. It appears on the other computer."))
            SeamArtwork(name: "okna-mirroring")
                .frame(maxWidth: 270, minHeight: 150, maxHeight: .infinity)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            HStack {
                Spacer()
                Button(action: showHow) {
                    HStack(spacing: 10) {
                        Text(L10n.text("Zobacz jak", "See how"))
                        Image(systemName: "play.fill").font(.system(size: 11))
                    }
                }
                .buttonStyle(OknaButtonStyle(prominent: true))
            }
        }
        .modifier(OknaCard())
    }
}

/// Stan połączenia: ten Mac, kropka statusu i komputer z Windows.
struct WindowsConnectionCard: View {
    @EnvironmentObject private var state: AppState
    let openConnection: () -> Void

    private var macName: String { state.settings.deviceName }
    private var pcName: String { state.peer?.name ?? "PC" }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                if state.peer != nil {
                    OknaCardHeading(title: L10n.text("Urządzenia są połączone", "Your devices are connected"),
                                    detail: L10n.text("\(macName) i \(pcName) są gotowe.", "\(macName) and \(pcName) are ready."))
                } else {
                    OknaCardHeading(title: L10n.text("Urządzenia nie są połączone", "Your devices are not connected"),
                                    detail: L10n.text("Uruchom Seam na komputerze z Windows i połącz go z tym Makiem.",
                                                      "Start Seam on your Windows computer and connect it to this Mac."))
                }
                Spacer(minLength: 0)
                SeamArtwork(name: "okna-connection").frame(width: 92).padding(.top, -6)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { devices; Spacer(minLength: 0); settingsButton }
                VStack(alignment: .leading, spacing: 12) { devices; settingsButton }
            }
        }
        .modifier(OknaCard())
    }

    private var devices: some View {
        HStack(spacing: 10) {
            SeamArtwork(name: "device-laptop").frame(width: 40)
            Text(macName).lineLimit(1).truncationMode(.tail).frame(maxWidth: 140, alignment: .leading).fixedSize()
            Circle().fill(state.peer != nil ? Color(red: 0.20, green: 0.78, blue: 0.35) : .gray)
                .frame(width: 9, height: 9)
                .accessibilityLabel(state.peer != nil ? L10n.text("Połączono", "Connected") : L10n.text("Brak połączenia", "Not connected"))
            Rectangle().fill(OknaTokens.mutedText.opacity(0.5)).frame(width: 18, height: 1)
            SeamArtwork(name: "device-monitor").frame(width: 34)
            Text(pcName).lineLimit(1).truncationMode(.tail).frame(maxWidth: 160, alignment: .leading).fixedSize()
        }
        .font(.system(size: 14))
    }

    private var settingsButton: some View {
        Button(L10n.text("Ustawienia połączenia", "Connection settings"), action: openConnection)
            .buttonStyle(OknaButtonStyle())
    }
}

/// Układ ekranów. Położenie Maca należy do aplikacji Windows (nie ma go w protokole),
/// więc tutaj tylko je pokazujemy i mówimy, gdzie je zmienić.
struct WindowsArrangementCard: View {
    let edge: ScreenEdge?

    private var description: String {
        switch edge {
        case .left: return L10n.text("Ekran Windows stoi po lewej od Maca", "The Windows screen is to the left of the Mac")
        case .right: return L10n.text("Ekran Windows stoi po prawej od Maca", "The Windows screen is to the right of the Mac")
        case .top: return L10n.text("Ekran Windows stoi nad Makiem", "The Windows screen is above the Mac")
        case .bottom: return L10n.text("Ekran Windows stoi pod Makiem", "The Windows screen is below the Mac")
        case nil: return L10n.text("Układ pojawi się po uruchomieniu drugiego ekranu", "The arrangement appears when the second display starts")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                OknaCardHeading(title: L10n.text("Wybierz układ ekranów", "Choose your screen layout"),
                                detail: L10n.text("Dopasuj układ do urządzeń na biurku.", "Match the layout to the devices on your desk."))
                Spacer(minLength: 0)
                SeamArtwork(name: "okna-arrangement").frame(width: 110).padding(.top, -4)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 18) {
                tiles
                VStack(alignment: .leading, spacing: 6) {
                    Text(description).font(.system(size: 14)).foregroundStyle(OknaTokens.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.text("Zmienisz go w Seam na Windowsie → Ekrany.", "Change it in Seam on Windows → Displays."))
                        .font(.caption).foregroundStyle(OknaTokens.mutedText.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .modifier(OknaCard())
    }

    /// Dwa kafle ekranów ustawione jak na biurku; ekran Windows leży po stronie `edge` względem Maca.
    @ViewBuilder private var tiles: some View {
        let side = edge ?? .right
        let macFirst = side == .right || side == .bottom
        let first = ScreenTile(label: macFirst ? "Mac" : "PC")
        let second = ScreenTile(label: macFirst ? "PC" : "Mac")
        if side == .top || side == .bottom {
            VStack(spacing: 4) { first; second }
        } else {
            HStack(spacing: 4) { first; second }
        }
    }
}

private struct ScreenTile: View {
    let label: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        Text(label)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(red: 0xEC / 255, green: 0xF8 / 255, blue: 0xDB / 255))
            .frame(width: 62, height: 46)
            .background {
                shape.fill(LinearGradient(stops: [.init(color: Color(red: 0x4F / 255, green: 0x9D / 255, blue: 0x28 / 255), location: 0),
                                                  .init(color: Color(red: 0x25 / 255, green: 0x85 / 255, blue: 0x2A / 255), location: 0.5),
                                                  .init(color: Color(red: 0x15 / 255, green: 0x63 / 255, blue: 0x2B / 255), location: 1)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay { shape.strokeBorder(Color(red: 0xDA / 255, green: 0xF5 / 255, blue: 0xB8 / 255), lineWidth: 1.5) }
    }
}
