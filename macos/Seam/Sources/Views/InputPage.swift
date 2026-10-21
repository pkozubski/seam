import SwiftUI

struct InputPage: View {
    @Environment(AppState.self) private var state

    private var status: String {
        guard state.settings.inputEnabled else { return L10n.text("Wyłączone", "Off") }
        guard state.peer != nil else { return L10n.text("Czeka na połączenie z Windowsem", "Waiting for Windows") }
        return state.cursorOnMac
            ? L10n.text("Aktywne · kursor jest na Macu", "Active · the pointer is on the Mac")
            : L10n.text("Aktywne · kursor jest na Windowsie", "Active · the pointer is on Windows")
    }

    var body: some View {
        @Bindable var state = state
        SettingsPageLayout(title: "Klawiatura i mysz", subtitle: "Jedna klawiatura i mysz dla obu komputerów.") {
            if !state.accessibilityGranted {
                PermissionBanner(title: "Brak uprawnienia Dostępność",
                                 message: "Bez niego Mac nie przyjmie ruchów myszy ani klawiszy z Windowsa.",
                                 grant: state.requestAccessibility,
                                 openSettings: state.openAccessibilitySettings)
            }
            FeatureHero(icon: "icon-control", title: "Przyjmuj klawiaturę i mysz z Windowsa",
                        status: status,
                        ok: state.settings.inputEnabled ? (state.peer != nil ? true : nil) : nil,
                        isOn: $state.settings.inputEnabled)
            SettingsGroup("Klawiatura") {
                SettingRow(title: "Zamień Ctrl ↔ Cmd",
                           subtitle: "Ctrl+C na klawiaturze PC działa jak ⌘C na Macu.") {
                    Toggle("", isOn: $state.settings.swapCtrlCmd).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup("Przewijanie") {
                SettingRow(title: "Kierunek",
                           subtitle: "„Automatycznie” uwzględnia naturalne przewijanie z ustawień Maca.") {
                    Picker("", selection: $state.settings.scrollDirection) {
                        ForEach(ScrollDirectionMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                Divider()
                SettingRow(title: "Szybkość",
                           subtitle: "\(state.settings.scrollSpeed.formatted(.number.precision(.fractionLength(0...2))))× · \(Int(40 * state.settings.scrollSpeed)) px"
                               + L10n.text(" na ząbek kółka", " per wheel notch")) {
                    Slider(value: $state.settings.scrollSpeed, in: 0.25...4, step: 0.25) {
                        Text("Szybkość")
                    } minimumValueLabel: {
                        Image(systemName: "tortoise").accessibilityHidden(true)
                    } maximumValueLabel: {
                        Image(systemName: "hare").accessibilityHidden(true)
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
            }
            Text("Skrót awaryjny, czułość myszy i położenie ekranów ustawiasz w aplikacji na Windowsie.")
                .font(.callout).foregroundStyle(.secondary)
                .padding(.leading, 4)
        }
    }
}
