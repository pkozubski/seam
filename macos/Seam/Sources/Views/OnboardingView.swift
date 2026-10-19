import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var state: AppState
    @State private var step = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Color.accentColor : Color.secondary.opacity(0.22))
                        .frame(width: index == step ? 28 : 10, height: 6)
                }
                Spacer()
                Text("Krok \(step + 1) z 3")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 28)

            Group {
                switch step {
                case 0: welcome
                case 1: pairing
                default: permissions
                }
            }
            .id(step)
            .transition(.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                if step > 0 { Button("Wstecz") { step -= 1 } }
                Spacer()
                if step < 2 {
                    Button("Dalej") { step += 1 }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else {
                    Button("Zakończ konfigurację") { state.completeOnboarding() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
            .padding(.top, 24)
        }
        .animation(reduceMotion ? nil : DesignTokens.interaction, value: step)
        .padding(32)
        .frame(width: 580, height: 460)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().interpolation(.high).frame(width: 64, height: 64)
            Text("Jedno biurko. Dwa komputery.")
                .font(.largeTitle.bold())
            Text("Seam połączy klawiaturę, mysz, schowek i dźwięk między Windowsem a tym Makiem — lokalnie, bez konta i bez chmury.")
                .font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Label("Dane pozostają w Twojej sieci lokalnej", systemImage: "house.and.flag")
                .foregroundStyle(.secondary)
        }
    }

    private var pairing: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sparuj komputer z Windows")
                .font(.largeTitle.bold())
            Text("Uruchom Seam na Windowsie i przepisz ten kod parowania. Sekret jest przechowywany w Pęku kluczy.")
                .font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            PairingCodeView()
            if let error = state.pairingStorageError {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nadaj wymagane uprawnienie")
                .font(.largeTitle.bold())
            Text("macOS musi zezwolić aplikacji na sterowanie kursorem i klawiaturą. Zgoda na dźwięk pojawi się dopiero przy pierwszym uruchomieniu strumienia.")
                .font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                StatusDot(ok: state.accessibilityGranted)
                Text(state.accessibilityGranted
                     ? L10n.text("Dostępność jest gotowa", "Accessibility is ready")
                     : L10n.text("Dostępność wymaga zgody", "Accessibility permission required"))
                    .font(.headline)
            }
            if !state.accessibilityGranted {
                HStack {
                    Button("Poproś o dostęp") { state.requestAccessibility() }
                        .buttonStyle(.borderedProminent)
                    Button("Otwórz Ustawienia systemowe") { state.openAccessibilitySettings() }
                }
                .controlSize(.large)
            }
        }
    }

}
