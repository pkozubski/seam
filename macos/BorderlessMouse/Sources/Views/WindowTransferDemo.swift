import SwiftUI

struct WindowTransferDemo: View {
    let edge: ScreenEdge
    let macName: String
    let peerName: String
    let isExample: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("Przeciągnij. I pracuj dalej.", "Drag it over. Keep working."))
                        .font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    Text(L10n.text("Chwyć okno za górny pasek i przenieś przez wspólną krawędź.",
                                   "Grab the title bar and drag the window across the shared edge."))
                        .foregroundStyle(.white.opacity(0.72)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(action: demonstrate) {
                    Label(L10n.text("Pokaż przejście", "Show the move"), systemImage: "play.fill")
                }
                .controlSize(.small)
                .help(L10n.text("Odtwórz przykład przeniesienia okna", "Preview moving a window"))
            }
            if isExample {
                Text(L10n.text("Przykładowy układ · aktualny pojawi się po uruchomieniu drugiego ekranu.",
                               "Example layout · your arrangement appears when the second display starts."))
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            WindowTransferDiagram(edge: edge, progress: progress, showHints: true)
                .frame(height: edge == .top || edge == .bottom ? 320 : 255)
            HStack {
                Label(edge == .left ? peerName : macName, systemImage: edge == .left ? "display" : "laptopcomputer")
                Spacer()
                Label(edge == .left ? macName : peerName, systemImage: edge == .left ? "laptopcomputer" : "display")
            }
            .font(.callout.weight(.medium)).foregroundStyle(.white.opacity(0.8))
            .lineLimit(1).truncationMode(.middle)
            Text(L10n.text("Okno przechodzi na drugi ekran. Aplikacja nadal działa na komputerze, na którym została otwarta.",
                           "The window moves to the other display. The app keeps running on the computer where you opened it."))
                .font(.callout).foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .modifier(WindowGuideSurface())
    }

    private func demonstrate() {
        progress = 0
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.2)) { progress = 1 }
    }
}
