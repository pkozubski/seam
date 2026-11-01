import SwiftUI

struct GeneralSettingsPane: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: SettingsChrome.sectionSpacing) {
            SettingsSection(title: L10n.text("This Mac", pl: "Ten Mac")) {
                SettingsCardRow(title: L10n.text("This Mac's name", pl: "Nazwa tego Maca"),
                                detail: L10n.text("Shown in the list in the Windows app.", pl: "Widoczna na liście w aplikacji Windows.")) {
                    TextField("", text: $state.settings.deviceName, prompt: Text(L10n.text("Name", pl: "Nazwa")))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }
            }
            SettingsSection(title: L10n.text("Startup", pl: "Uruchamianie")) {
                SettingsCardRow(title: L10n.text("Open at login", pl: "Uruchamiaj przy logowaniu"),
                                detail: state.loginItemError ?? state.loginItemStatus) {
                    SettingsSwitch(isOn: $state.settings.launchAtLogin)
                }
                SettingsRowDivider()
                SettingsCardRow(title: L10n.text("Keep the window closed at login", pl: "Przy autostarcie nie otwieraj okna"),
                                detail: L10n.text("The app waits in the menu bar.", pl: "Aplikacja czeka w pasku menu.")) {
                    SettingsSwitch(isOn: $state.settings.startHidden)
                }
                .disabled(!state.settings.launchAtLogin)
                .opacity(state.settings.launchAtLogin ? 1 : 0.5)
            }
        }
    }
}

/// Ustawienia → Język.
struct LanguageSettingsPane: View {
    var body: some View { LanguageSettingsSection() }
}

/// Język aplikacji; obowiązuje od następnego uruchomienia.
private struct LanguageSettingsSection: View {
    @State private var language = L10n.language
    @State private var needsRestart = L10n.needsRestart

    var body: some View {
        SettingsSection(title: L10n.text("Language", pl: "Język")) {
            SettingsCardRow(title: L10n.text("App language", pl: "Język aplikacji"),
                            detail: needsRestart
                                ? L10n.text("Restart Seam to apply the change.", pl: "Uruchom Seam ponownie, aby zastosować zmianę.")
                                : L10n.text("System follows the language order in macOS settings.",
                                            pl: "Systemowy idzie za kolejnością języków w ustawieniach macOS.")) {
                HStack(spacing: 8) {
                    if needsRestart {
                        Button(L10n.text("Restart", pl: "Uruchom ponownie"), action: Self.relaunch)
                            .modifier(NativeActionStyle())
                            .controlSize(.small)
                    }
                    Picker("", selection: $language) {
                        ForEach(AppLanguage.allCases) { Text(verbatim: $0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
        }
        .onChange(of: language) { _, newValue in
            L10n.language = newValue
            needsRestart = L10n.needsRestart
        }
    }

    /// Nowa kopia startuje dopiero po zakończeniu tej, bo port sterowania może mieć tylko jeden proces.
    private static func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; open \"$0\"",
                             Bundle.main.bundlePath]
        try? process.run()
        NSApplication.shared.terminate(nil)
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
                    Button(L10n.text("Check now", pl: "Sprawdź teraz"), action: state.checkForUpdates)
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
            SettingsSection(title: L10n.text("Automatic", pl: "Automatycznie")) {
                SettingsCardRow(title: L10n.text("Check automatically", pl: "Sprawdzaj automatycznie"),
                                detail: Updater.automaticUpdatesDescription) {
                    SettingsSwitch(isOn: $state.settings.autoCheckUpdates)
                }
                SettingsRowDivider()
                SettingsCardRow(title: L10n.text("Update channel", pl: "Kanał aktualizacji"),
                                detail: L10n.text("Set by the build you installed.", pl: "Zależy od zainstalowanej wersji.")) {
                    Label(Updater.isDevChannel ? L10n.text("Test", pl: "Testowy") : L10n.text("Stable", pl: "Stabilny"),
                          systemImage: Updater.isDevChannel ? "hammer.fill" : "checkmark.shield.fill")
                        .font(.subheadline).foregroundStyle(.secondary)
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
        L10n.text("Version \(Updater.currentVersion)", pl: "Wersja \(Updater.currentVersion)")
            + (Updater.isDevChannel ? L10n.text(" · test channel", pl: " · kanał testowy") : L10n.text(" · stable channel", pl: " · kanał stabilny"))
    }

    private var notes: (title: String, markdown: String, link: URL?)? {
        if case .available(let release) = updater.state, !release.notes.isEmpty {
            return (L10n.text("What's new in \(release.version)", pl: "Co nowego w \(release.version)"), release.notes, release.pageURL)
        }
        if let installed = updater.installedNotes {
            return (L10n.text("What's new in \(Updater.currentVersion)", pl: "Co nowego w \(Updater.currentVersion)"), installed, nil)
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
        case .idle: return L10n.text("Not checked yet.", pl: "Jeszcze nie sprawdzono.")
        case .checking: return L10n.text("Checking…", pl: "Sprawdzanie…")
        case .upToDate(let when): return L10n.text("You're up to date · checked \(when)", pl: "Masz najnowszą wersję · sprawdzono \(when)")
        case .available(let r): return L10n.text("Version \(r.version) is ready to install.", pl: "Wersja \(r.version) jest gotowa do instalacji.")
        case .downloading:
            guard progress.totalBytes > 0 else { return L10n.text("Downloading…", pl: "Pobieranie…") }
            let received = ByteCountFormatter.string(fromByteCount: progress.receivedBytes, countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: progress.totalBytes, countStyle: .file)
            return L10n.text("Downloading · \(received) of \(total)", pl: "Pobieranie · \(received) z \(total)")
        case .verifying: return L10n.text("Checking the signature and checksum…", pl: "Sprawdzanie podpisu i sumy kontrolnej…")
        case .installing: return L10n.text("Installing — the app will restart.", pl: "Instalowanie – aplikacja uruchomi się ponownie.")
        case .updated(let version): return L10n.text("Updated to version \(version).", pl: "Zaktualizowano do wersji \(version).")
        case .failed(let msg): return L10n.text("Error: \(msg)", pl: "Błąd: \(msg)")
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
            SettingsSection(title: L10n.text("Network", pl: "Sieć")) {
                SettingsCardRow(title: L10n.text("TCP port", pl: "Port TCP"),
                                detail: portError ?? L10n.localized("Changing it restarts the listener.")) {
                    HStack(spacing: 8) {
                        TextField("", text: $portText, prompt: Text(verbatim: "47800"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                            .onSubmit(applyPort)
                        Button(L10n.text("Apply", pl: "Zastosuj"), action: applyPort)
                            .modifier(NativeActionStyle())
                            .controlSize(.small)
                    }
                }
            }
            SettingsSection(title: L10n.text("Update signing", pl: "Podpis aktualizacji")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("Your own signing certificate", pl: "Własny certyfikat podpisu")).font(.body)
                    Text(L10n.text(
                        "The free beta has a stable bundle signature and a separate ECDSA update signature, but is not notarized by Apple. Leave the field below empty unless you sign local builds with your own certificate.",
                        pl: "Bezpłatna beta ma stały podpis bundle i osobny podpis ECDSA aktualizacji, ale nie jest notaryzowana przez Apple. Pole poniżej zostaw puste, chyba że podpisujesz lokalne buildy własnym certyfikatem."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField("", text: $state.settings.codesignIdentity,
                              prompt: Text(L10n.text("Optional certificate", pl: "Opcjonalny własny certyfikat")))
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
            portError = L10n.text("Enter a number between 1024 and 65535.", pl: "Wpisz liczbę od 1024 do 65535.")
        }
    }
}
