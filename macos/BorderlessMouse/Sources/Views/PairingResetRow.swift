import SwiftUI

struct PairingResetRow: View {
    @EnvironmentObject private var state: AppState
    @State private var confirming = false

    var body: some View {
        SettingRow(title: "Unieważnij dostęp",
                   subtitle: "Nowy kod natychmiast rozłączy komputer i unieważni poprzedni kod.") {
            Button("Wygeneruj nowy kod", role: .destructive) { confirming = true }
        }
        .alert("Wygenerować nowy kod parowania?", isPresented: $confirming) {
            Button("Anuluj", role: .cancel) { }
            Button("Wygeneruj", role: .destructive) { state.regeneratePairingCode() }
        } message: {
            Text("Windows będzie wymagał ponownego wpisania kodu.")
        }
    }
}
