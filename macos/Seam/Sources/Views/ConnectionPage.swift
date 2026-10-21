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
                        SeamArtwork(name: "seam-windows")
                            .padding(26)
                            .background(EllipticalGradient(colors: [DesignTokens.studioLight.opacity(0.18), .clear],
                                                           endRadiusFraction: 0.5))
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                        ConnectionOverview(openWindows: openWindows)
                            .frame(width: geometry.size.width < 800 ? 300 : 340)
                    }
                    .frame(minHeight: max(370, geometry.size.height - 160))
                    VStack(spacing: 12) {
                        Text(state.peer != nil
                             ? L10n.text("Wszystko gotowe. Pracuj jak na jednym komputerze.", "All set. Work as if it were one computer.")
                             : L10n.text("Uruchom aplikację na Windowsie i połącz oba komputery.", "Open the app on Windows and connect your computers."))
                            .font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button(L10n.text("Parowanie i szczegóły połączenia", "Pairing and connection details")) { showDetails = true }
                            .buttonStyle(.link).font(.caption)
                    }
                    if state.peer == nil {
                        SettingsGroup("Bezpieczne parowanie") { PairingCodeView() }
                            .frame(maxWidth: 640)
                    }
                }
                .padding(.horizontal, 28).padding(.bottom, 76)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showDetails) {
            ConnectionDetails().environment(state)
        }
    }
}
