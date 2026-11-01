import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var state
    @State private var step = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `initialStep` służy podglądowi UI (`--ui-onboarding-step`), aplikacja zaczyna od 0.
    init(initialStep: Int = 0) { _step = State(initialValue: initialStep) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Color.accentColor : Color.secondary.opacity(0.22))
                        .frame(width: index == step ? 28 : 10, height: 6)
                }
                Spacer()
                Text("Step \(step + 1) of 3")
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
                if step > 0 { Button("Back") { step -= 1 } }
                Spacer()
                if step < 2 {
                    Button("Continue") { step += 1 }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else {
                    Button("Finish setup") { state.completeOnboarding() }
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
            Text("One desk. Two computers.")
                .font(.largeTitle.bold())
            Text("Seam connects your keyboard, mouse, clipboard and audio between Windows and this Mac — locally, without an account or cloud.")
                .font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Label("Your data stays on your local network", systemImage: "house.and.flag")
                .foregroundStyle(.secondary)
        }
    }

    private var pairing: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pair your Windows PC")
                .font(.largeTitle.bold())
            Text("Open Seam on Windows and enter this pairing code. The secret is protected in Keychain.")
                .font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            PairingCodeView()
            if let error = state.pairingStorageError {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Grant the required permission")
                .font(.largeTitle.bold())
            Text("macOS must allow the app to control the pointer and keyboard. Audio permission appears when streaming starts for the first time.")
                .font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                StatusDot(ok: state.accessibilityGranted)
                Text(state.accessibilityGranted
                     ? L10n.text("Accessibility is ready", pl: "Dostępność jest gotowa")
                     : L10n.text("Accessibility permission required", pl: "Dostępność wymaga zgody"))
                    .font(.headline)
            }
            if !state.accessibilityGranted {
                HStack {
                    Button("Request access") { state.requestAccessibility() }
                        .buttonStyle(.borderedProminent)
                    Button("Open System Settings") { state.openAccessibilitySettings() }
                }
                .controlSize(.large)
            }
        }
    }

}
