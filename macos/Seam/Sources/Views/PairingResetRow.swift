import SwiftUI

struct PairingResetRow: View {
    @Environment(AppState.self) private var state
    @State private var confirming = false

    var body: some View {
        SettingRow(title: "Revoke access",
                   subtitle: "A new code immediately disconnects the PC and revokes the previous code.") {
            Button("Generate new code", role: .destructive) { confirming = true }
        }
        .alert("Generate a new pairing code?", isPresented: $confirming) {
            Button("Cancel", role: .cancel) { }
            Button("Generate", role: .destructive) { state.regeneratePairingCode() }
        } message: {
            Text("Windows will require the new code.")
        }
    }
}
