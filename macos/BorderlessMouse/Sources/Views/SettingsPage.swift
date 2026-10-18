import SwiftUI

struct SettingsPage: View {
    @EnvironmentObject private var state: AppState
    @State private var portText = ""
    @State private var showAdvanced = false
    @State private var portError: String?

    var body: some View {
        SettingsPageLayout(title: "Ustawienia", subtitle: "Małe ustawienia. Twoje codzienne biurko.") {
            SettingsGroup("Ogólne") {
                SettingRow(title: "Nazwa tego Maca", subtitle: "Widoczna na liście w aplikacji Windows.") {
                    TextField("", text: $state.settings.deviceName, prompt: Text("Nazwa"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }
                SettingRow(title: "Port TCP", subtitle: portError ?? L10n.localized("Zmiana restartuje nasłuchiwanie.")) {
                    HStack {
                        TextField("", text: $portText, prompt: Text("47800"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                            .onSubmit(applyPort)
                        Button("Zastosuj", action: applyPort)
                    }
                }
            }
            SettingsGroup("Uruchamianie") {
                SettingRow(title: "Uruchamiaj przy logowaniu", subtitle: state.loginItemError ?? state.loginItemStatus) {
                    Toggle("", isOn: $state.settings.launchAtLogin).labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: "Przy autostarcie nie otwieraj okna", subtitle: "Aplikacja czeka w pasku menu.") {
                    Toggle("", isOn: $state.settings.startHidden).labelsHidden().toggleStyle(.switch)
                        .disabled(!state.settings.launchAtLogin)
                }
            }
            SettingsGroup("Aktualizacje") {
                SettingRow(title: L10n.text("Wersja \(Updater.versionDescription)", "Version \(Updater.versionDescription)"), subtitle: statusText) {
                    HStack(spacing: 8) {
                        switch state.updater.state {
                        case .checking:
                            ProgressView().controlSize(.small)
                        case .available:
                            Button("Zainstaluj i uruchom ponownie") { state.installUpdate() }
                                .buttonStyle(.borderedProminent)
                        case .downloading(let p):
                            ProgressView(value: p).frame(width: 120)
                        case .installing:
                            ProgressView().controlSize(.small)
                        default:
                            Button("Sprawdź teraz") { state.checkForUpdates() }
                        }
                    }
                }
                if case .available(let release) = state.updater.state, !release.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(release.notes.prefix(600))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(8)
                            .textSelection(.enabled)
                        Link("Zobacz wydanie na GitHubie", destination: release.pageURL).font(.caption)
                    }
                }
                SettingRow(title: "Sprawdzaj automatycznie", subtitle: Updater.automaticUpdatesDescription) {
                    Toggle("", isOn: $state.settings.autoCheckUpdates).labelsHidden().toggleStyle(.switch)
                }
                DisclosureGroup("Zaawansowane: podpisywanie aktualizacji", isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text(
                            "Bezpłatna beta ma stały podpis bundle i osobny podpis ECDSA aktualizacji, ale nie jest notaryzowana przez Apple. Pole poniżej zostaw puste, chyba że podpisujesz lokalne buildy własnym certyfikatem.",
                            "The free beta has a stable bundle signature and a separate ECDSA update signature, but is not notarized by Apple. Leave the field below empty unless you sign local builds with your own certificate."))
                            .font(.caption).foregroundStyle(.secondary)
                        TextField("", text: $state.settings.codesignIdentity, prompt: Text("Opcjonalny własny certyfikat"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.top, 6)
                }
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

    private var statusText: String {
        switch state.updater.state {
        case .idle: return L10n.text("Kliknij „Sprawdź teraz”, aby sprawdzić nowe wydania.", "Select Check now to look for new releases.")
        case .checking: return L10n.text("Sprawdzanie…", "Checking…")
        case .upToDate(let when): return L10n.text("Masz najnowszą wersję · sprawdzono \(when)", "Up to date · checked \(when)")
        case .available(let r): return L10n.text("Dostępna wersja \(r.version)", "Version \(r.version) available")
        case .downloading: return L10n.text("Pobieranie aktualizacji…", "Downloading update…")
        case .installing: return L10n.text("Instalowanie – aplikacja uruchomi się ponownie.", "Installing — the app will restart.")
        case .failed(let msg): return L10n.text("Błąd: \(msg)", "Error: \(msg)")
        }
    }
}
