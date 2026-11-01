import SwiftUI

struct ConnectionPage: View {
    @Environment(AppState.self) private var state
    var openWindows: () -> Void = {}
    @State private var showDetails = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    HStack(spacing: 12) {
                        SeamArtwork(name: "hero-connection")
                            .padding(6)
                            .background(EllipticalGradient(colors: [ConnectionTokens.cyanGlow.opacity(0.28), .clear],
                                                           endRadiusFraction: 0.5))
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                        ConnectionOverview(openWindows: openWindows)
                            .frame(width: geometry.size.width < 800 ? 300 : 340)
                    }
                    .frame(minHeight: max(370, geometry.size.height - 160))
                    VStack(spacing: 12) {
                        Text(state.peer != nil
                             ? L10n.text("All set. Work as if it were one computer.", pl: "Wszystko gotowe. Pracuj jak na jednym komputerze.")
                             : L10n.text("Open the app on Windows and connect your computers.", pl: "Uruchom aplikację na Windowsie i połącz oba komputery."))
                            .font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button(L10n.text("Pairing and connection details", pl: "Parowanie i szczegóły połączenia")) { showDetails = true }
                            .buttonStyle(.link).font(.caption)
                    }
                    if state.peer == nil {
                        SettingsGroup("Secure pairing") { PairingCodeView() }
                            .frame(maxWidth: 640)
                    }
                }
                .padding(.horizontal, 28).padding(.bottom, 76)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
        }
        .tint(ConnectionTokens.accent)
        .sheet(isPresented: $showDetails) {
            ConnectionDetails().environment(state)
        }
    }
}
