import SwiftUI

struct GeneralSettingsPane: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: SettingsChrome.sectionSpacing) {
            SettingsSection(title: L10n.text("Ten Mac", "This Mac")) {
                SettingsCardRow(title: L10n.text("Nazwa tego Maca", "This Mac's name"),
                                detail: L10n.text("Widoczna na liście w aplikacji Windows.", "Shown in the list in the Windows app.")) {
                    TextField("", text: $state.settings.deviceName, prompt: Text(L10n.text("Nazwa", "Name")))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }
            }
            SettingsSection(title: L10n.text("Uruchamianie", "Startup")) {
                SettingsCardRow(title: L10n.text("Uruchamiaj przy logowaniu", "Open at login"),
                                detail: state.loginItemError ?? state.loginItemStatus) {
                    SettingsSwitch(isOn: $state.settings.launchAtLogin)
                }
                SettingsRowDivider()
                SettingsCardRow(title: L10n.text("Przy autostarcie nie otwieraj okna", "Keep the window closed at login"),
                                detail: L10n.text("Aplikacja czeka w pasku menu.", "The app waits in the menu bar.")) {
                    SettingsSwitch(isOn: $state.settings.startHidden)
                }
                .disabled(!state.settings.launchAtLogin)
                .opacity(state.settings.launchAtLogin ? 1 : 0.5)
            }
        }
    }
}

struct UpdatesSettingsPane: View {
    @Environment(AppState.self) private var state
    @ObservedObject var updater: Updater

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: SettingsChrome.sectionSpacing) {
            SettingsCard {
                HStack(spacing: 14) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable().interpolation(.high).scaledToFit()
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: "seam").font(.title3.weight(.semibold))
                        Text(verbatim: versionLine).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button(L10n.text("Sprawdź teraz", "Check now"), action: state.checkForUpdates)
                        .modifier(NativeActionStyle())
                        .controlSize(.small)
                        .disabled(updater.state == .checking || updater.state.isBusy)
                }
                .padding(16)
                SettingsRowDivider()
                UpdateStatusRow(updater: updater, progress: updater.progress)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            SettingsSection(title: L10n.text("Automatycznie", "Automatic")) {
                SettingsCardRow(title: L10n.text("Sprawdzaj automatycznie", "Check automatically"),
                                detail: Updater.automaticUpdatesDescription) {
                    SettingsSwitch(isOn: $state.settings.autoCheckUpdates)
                }
            }
            if let notes {
                ReleaseNotesView(title: notes.title, markdown: notes.markdown, link: notes.link)
            }
        }
        // Opening the page checks once, so it never shows a stale "not checked yet".
        .task { if updater.state == .idle { state.checkForUpdates() } }
    }

    private var versionLine: String {
        L10n.text("Wersja \(Updater.currentVersion)", "Version \(Updater.currentVersion)")
            + (Updater.isDevChannel ? L10n.text(" · kanał testowy", " · test channel") : L10n.text(" · kanał stabilny", " · stable channel"))
    }

    private var notes: (title: String, markdown: String, link: URL?)? {
        if case .available(let release) = updater.state, !release.notes.isEmpty {
            return (L10n.text("Co nowego w \(release.version)", "What's new in \(release.version)"), release.notes, release.pageURL)
        }
        if let installed = updater.installedNotes {
            return (L10n.text("Co nowego w \(Updater.currentVersion)", "What's new in \(Updater.currentVersion)"), installed, nil)
        }
        return nil
    }
}

/// The current step in words, with the bar while an install runs.
private struct UpdateStatusRow: View {
    @ObservedObject var updater: Updater
    @ObservedObject var progress: UpdateProgress

    private var showsBar: Bool {
        if updater.state.isBusy { return true }
        if case .updated = updater.state { return progress.value > 0 }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                icon.frame(width: 16)
                Text(verbatim: text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if showsBar {
                    Text(progress.value, format: .percent.precision(.fractionLength(0)))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if showsBar {
                UpdateProgressBar(progress: progress)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showsBar)
    }

    @ViewBuilder private var icon: some View {
        switch updater.state {
        case .checking:
            ProgressView().controlSize(.mini)
        case .upToDate, .updated:
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
        case .available, .downloading, .verifying, .installing:
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(DesignTokens.accent)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .idle:
            Image(systemName: "clock").foregroundStyle(.secondary)
        }
    }

    private var text: String {
        switch updater.state {
        case .idle: return L10n.text("Jeszcze nie sprawdzono.", "Not checked yet.")
        case .checking: return L10n.text("Sprawdzanie…", "Checking…")
        case .upToDate(let when): return L10n.text("Masz najnowszą wersję · sprawdzono \(when)", "You're up to date · checked \(when)")
        case .available(let r): return L10n.text("Wersja \(r.version) jest gotowa do instalacji.", "Version \(r.version) is ready to install.")
        case .downloading:
            guard progress.totalBytes > 0 else { return L10n.text("Pobieranie…", "Downloading…") }
            let received = ByteCountFormatter.string(fromByteCount: progress.receivedBytes, countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: progress.totalBytes, countStyle: .file)
            return L10n.text("Pobieranie · \(received) z \(total)", "Downloading · \(received) of \(total)")
        case .verifying: return L10n.text("Sprawdzanie podpisu i sumy kontrolnej…", "Checking the signature and checksum…")
        case .installing: return L10n.text("Instalowanie – aplikacja uruchomi się ponownie.", "Installing — the app will restart.")
        case .updated(let version): return L10n.text("Zaktualizowano do wersji \(version).", "Updated to version \(version).")
        case .failed(let msg): return L10n.text("Błąd: \(msg)", "Error: \(msg)")
        }
    }
}

struct AdvancedSettingsPane: View {
    @Environment(AppState.self) private var state
    @State private var portText = ""
    @State private var portError: String?

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: SettingsChrome.sectionSpacing) {
            SettingsSection(title: L10n.text("Sieć", "Network")) {
                SettingsCardRow(title: L10n.text("Port TCP", "TCP port"),
                                detail: portError ?? L10n.localized("Zmiana restartuje nasłuchiwanie.")) {
                    HStack(spacing: 8) {
                        TextField("", text: $portText, prompt: Text(verbatim: "47800"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                            .onSubmit(applyPort)
                        Button(L10n.text("Zastosuj", "Apply"), action: applyPort)
                            .modifier(NativeActionStyle())
                            .controlSize(.small)
                    }
                }
            }
            SettingsSection(title: L10n.text("Podpis aktualizacji", "Update signing")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("Własny certyfikat podpisu", "Your own signing certificate")).font(.body)
                    Text(L10n.text(
                        "Bezpłatna beta ma stały podpis bundle i osobny podpis ECDSA aktualizacji, ale nie jest notaryzowana przez Apple. Pole poniżej zostaw puste, chyba że podpisujesz lokalne buildy własnym certyfikatem.",
                        "The free beta has a stable bundle signature and a separate ECDSA update signature, but is not notarized by Apple. Leave the field below empty unless you sign local builds with your own certificate."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField("", text: $state.settings.codesignIdentity,
                              prompt: Text(L10n.text("Opcjonalny własny certyfikat", "Optional certificate")))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .padding(.top, 2)
                }
                .padding(16)
            }
        }
        .onAppear { portText = String(state.settings.controlPort) }
    }

    private func applyPort() {
        if let p = Int(portText), (1024...65535).contains(p) {
            state.settings.controlPort = p
            portError = nil
        } else {
            portError = L10n.text("Wpisz liczbę od 1024 do 65535.", "Enter a number between 1024 and 65535.")
        }
    }
}
