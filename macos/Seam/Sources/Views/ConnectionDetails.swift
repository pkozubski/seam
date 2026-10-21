import SwiftUI

struct ConnectionDetails: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(L10n.text("Połączenie", "Connection")).font(.title2)
            Text(state.statusSummary.text).foregroundStyle(state.statusSummary.color)
            if state.peer != nil {
                Button(L10n.text("Rozłącz komputery", "Disconnect computers"), action: state.disconnectPeer)
            }
            PairingCodeView()
            PairingResetRow()
            Divider()
            LabeledContent("TCP", value: "\(state.settings.controlPort) · AES-256-GCM")
            HStack { Spacer(); Button(L10n.text("Gotowe", "Done")) { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 520)
    }
}
