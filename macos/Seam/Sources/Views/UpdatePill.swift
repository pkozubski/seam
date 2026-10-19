import SwiftUI

/// Version status that turns into the install button, then into the progress bar, in one capsule.
struct UpdatePill: View {
    @ObservedObject private var updater: Updater
    @ObservedObject private var progress: UpdateProgress
    private let install: () -> Void

    init(updater: Updater, install: @escaping () -> Void) {
        _updater = ObservedObject(wrappedValue: updater)
        _progress = ObservedObject(wrappedValue: updater.progress)
        self.install = install
    }

    private enum Face: Equatable { case status, ready, progress }

    private var face: Face {
        if case .available = updater.state { return .ready }
        if updater.state.isBusy { return .progress }
        if case .updated = updater.state, progress.value > 0 { return .progress }
        return .status
    }

    var body: some View {
        Group {
            switch face {
            case .ready:
                Button(action: install) {
                    Label(L10n.text("Zaktualizuj i uruchom ponownie", "Update & restart"), systemImage: "arrow.down.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(DesignTokens.accent)
                        .padding(.horizontal, 12)
                        .frame(height: SettingsChrome.capsuleHeight)
                        .background(Capsule().fill(DesignTokens.accent.opacity(0.18)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassCapsule(interactive: true)
            case .progress:
                UpdateProgressBar(progress: progress, trackHeight: 10)
                    .frame(width: 112)
                    .padding(.horizontal, 12)
                    .frame(height: SettingsChrome.capsuleHeight)
                    .glassCapsule()
            case .status:
                status
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 12)
                    .frame(height: SettingsChrome.capsuleHeight)
                    .glassCapsule()
                    .help(help)
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.18), value: face)
    }

    @ViewBuilder private var status: some View {
        switch updater.state {
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(L10n.text("Sprawdzanie…", "Checking…"))
            }
        case .upToDate:
            pillLabel(L10n.text("Aktualna", "Up to date"), symbol: "checkmark.seal.fill", tint: .green)
        case .updated:
            pillLabel(L10n.text("Zaktualizowano", "Updated"), symbol: "checkmark.seal.fill", tint: DesignTokens.accent)
        case .failed:
            pillLabel(L10n.text("Błąd sprawdzania", "Check failed"), symbol: "exclamationmark.triangle.fill", tint: .orange)
        default:
            pillLabel(L10n.text("Nie sprawdzono", "Not checked"), symbol: "clock", tint: .secondary)
        }
    }

    private func pillLabel(_ title: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(verbatim: title)
        }
    }

    private var help: String {
        switch updater.state {
        case .failed(let msg): return msg
        case .upToDate(let when): return L10n.text("Sprawdzono \(when)", "Checked \(when)")
        default: return "seam \(Updater.versionDescription)"
        }
    }
}

/// Accent dot shown where updates live while a new version waits.
struct UpdateBadge: View {
    @ObservedObject var updater: Updater

    var body: some View {
        if case .available = updater.state {
            Circle()
                .fill(DesignTokens.accent)
                .frame(width: 7, height: 7)
                .accessibilityLabel(L10n.text("Dostępna aktualizacja", "Update available"))
        }
    }
}
