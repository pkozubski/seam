import SwiftUI

struct PairingCodeView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Wpisz ten kod na komputerze z Windows. Zachowaj go dla siebie.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    code
                    Spacer(minLength: 0)
                    copyButton
                }
                VStack(alignment: .leading, spacing: 12) {
                    code
                    copyButton
                }
            }
            .padding(14)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            if let error = state.pairingStorageError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.red)
            }
        }
        .task(id: copied) {
            guard copied else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            copied = false
        }
    }

    private var code: some View {
        Text(state.pairingCode)
            .font(.system(.callout, design: .monospaced).weight(.semibold))
            .textSelection(.enabled)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel(L10n.text("Kod parowania", "Pairing code"))
            .accessibilityValue(state.pairingCode)
    }

    private var copyButton: some View {
        Button(action: copy) {
            Label(copied ? L10n.text("Skopiowano", "Copied") : L10n.text("Kopiuj kod", "Copy code"),
                  systemImage: copied ? "checkmark" : "doc.on.doc")
                .frame(minWidth: 95)
                .contentTransition(.opacity)
        }
        .modifier(NativeActionStyle())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: copied)
    }

    private func copy() {
        state.copyPairingCode()
        copied = true
    }
}
