import SwiftUI

struct PermissionsPage: View {
    @Environment(AppState.self) private var state

    var body: some View {
        SettingsPageLayout(title: "Permissions", subtitle: summary) {
            SettingsGroup("For Keyboard & mouse") {
                SettingRow(title: "Accessibility",
                           subtitle: state.accessibilityGranted
                           ? L10n.text("Ready. You can control your Mac from Windows.", pl: "Gotowe. Możesz sterować Makiem z Windowsa.")
                           : L10n.text("Required. System Settings → Privacy & Security → Accessibility.", pl: "Wymagane. Ustawienia → Prywatność i ochrona → Dostępność.")) {
                    HStack(spacing: 8) {
                        StatusDot(ok: state.accessibilityGranted)
                        if state.accessibilityGranted {
                            Text("Ready").foregroundStyle(.secondary)
                        } else {
                            Button("Request") { state.requestAccessibility() }
                            Button("Settings") { state.openAccessibilitySettings() }
                        }
                    }
                }
            }
            SettingsGroup("For Audio") {
                SettingRow(title: "System audio recording",
                           subtitle: state.audioPermissionSubtitle) {
                    HStack(spacing: 8) {
                        if case .checking = state.audioPermission {
                            ProgressView().controlSize(.small)
                        } else {
                            StatusDot(ok: state.audioPermissionGranted)
                        }
                        if state.audioPermission.isGranted {
                            Text("Ready").foregroundStyle(.secondary)
                            Button("Check") { state.checkAudioPermission(force: true) }
                        } else {
                            Button("Request") { state.checkAudioPermission(force: true) }
                            if state.audioPermissionGranted == false {
                                Button("Repair") { state.repairAudioPermission() }
                            }
                            Button("Settings") { state.openAudioCaptureSettings() }
                        }
                    }
                    .disabled({ if case .checking = state.audioPermission { return true }; return false }())
                }
            }
            SettingsGroup("For Windows") {
                SettingRow(title: "Screen Recording",
                           subtitle: state.screenCaptureGranted
                           ? L10n.text("Granted — the Mac can show its virtual display on Windows.", pl: "Nadane – Mac może pokazać ekran wirtualny na Windowsie.")
                           : L10n.text("Needed only for the virtual display. Relaunch the app after granting it.", pl: "Potrzebne tylko dla ekranu wirtualnego. Po nadaniu zgody uruchom aplikację ponownie.")) {
                    HStack(spacing: 8) {
                        StatusDot(ok: state.screenCaptureGranted ? true : nil)
                        if state.screenCaptureGranted {
                            Text("Ready").foregroundStyle(.secondary)
                        } else {
                            Button("Request") { state.requestScreenCapture() }
                            Button("Settings") { state.openScreenCaptureSettings() }
                        }
                    }
                }
            }
        }
        .onAppear { state.checkAudioPermission(force: false) }
    }

    private var summary: String {
        let granted = [state.accessibilityGranted, state.audioPermission.isGranted, state.screenCaptureGranted].filter { $0 }.count
        return L10n.text("Granted: \(granted) of 3. Each permission is needed by one feature only.",
                         pl: "Nadane: \(granted) z 3. Każde uprawnienie potrzebne jest tylko jednej funkcji.")
    }
}
