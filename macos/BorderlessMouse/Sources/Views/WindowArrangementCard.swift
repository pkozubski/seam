import SwiftUI

struct WindowArrangementCard: View {
    let edge: ScreenEdge?

    private var placement: String {
        switch edge {
        case .left: return L10n.text("Drugi ekran po lewej", "Second display on the left")
        case .right: return L10n.text("Drugi ekran po prawej", "Second display on the right")
        case .top: return L10n.text("Drugi ekran nad Makiem", "Second display above the Mac")
        case .bottom: return L10n.text("Drugi ekran pod Makiem", "Second display below the Mac")
        case nil: return L10n.text("Przykładowy układ ekranów", "Example display arrangement")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.text("Z której strony jest drugi ekran?", "Which side is your other display on?"))
                .font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text(L10n.text("Ustaw ekrany tak, jak stoją na biurku. To określa, przez którą krawędź przeciągniesz okno.",
                           "Arrange the displays as they sit on your desk. This decides which edge you move windows across."))
                .foregroundStyle(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 28) {
                WindowTransferDiagram(edge: edge ?? .right, compact: true, showWindow: false)
                    .frame(maxWidth: .infinity).frame(height: 140)
                VStack(alignment: .leading, spacing: 10) {
                    Text(placement).font(.headline)
                    Text(L10n.text("Na komputerze z Windows otwórz seam → Ekrany i ustaw położenie Maca.",
                                   "On your Windows computer, open seam → Displays and set the Mac's position."))
                        .font(.callout).foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
                    Label(L10n.text("Windows  ›  seam  ›  Ekrany", "Windows  ›  seam  ›  Displays"), systemImage: "display")
                        .font(.caption.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .modifier(WindowGuideSurface())
    }
}
