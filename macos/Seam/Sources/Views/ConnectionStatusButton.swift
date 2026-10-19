import SwiftUI

struct ConnectionStatusButton: View {
    @ObservedObject var state: AppState
    let action: () -> Void
    @State private var hovering = false
    private var connected: Bool { state.peer != nil }
    private var color: Color { state.listenError != nil ? .orange : (connected ? Color(red: 0.57, green: 0.73, blue: 0.56) : .gray) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                SeamArtwork(name: "icon-connection").frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                Text(state.listenError != nil ? L10n.text("Błąd", "Error") : (connected ? L10n.text("Połączono", "Connected") : L10n.text("Oczekiwanie", "Waiting")))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 98, height: 98)
            .background(
                LinearGradient(colors: [color.opacity(hovering ? 0.9 : 0.65), Color(red: 0.12, green: 0.15, blue: 0.13), Color(red: 0.07, green: 0.08, blue: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Circle())
            .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.8), color.opacity(0.35), .white.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(L10n.text("Stan i szczegóły połączenia", "Connection status and details"))
        .accessibilityLabel(state.statusSummary.text)
        .accessibilityHint(L10n.text("Otwiera szczegóły połączenia", "Opens connection details"))
        .frame(width: 126, height: 126)
        .preferredColorScheme(.dark)
    }
}
