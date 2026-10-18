import SwiftUI

struct PermissionsPage: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        SettingsPageLayout(title: "Uprawnienia", subtitle: "Zdecyduj, do czego BorderlessMouse ma dostęp.") {
            SettingsGroup("Sterowanie myszą i klawiaturą") {
                SettingRow(title: "Dostępność",
                           subtitle: state.accessibilityGranted
                           ? L10n.text("Gotowe. Możesz sterować Makiem z Windowsa.", "Ready. You can control your Mac from Windows.")
                           : L10n.text("Wymagane. Ustawienia → Prywatność i ochrona → Dostępność.", "Required. System Settings → Privacy & Security → Accessibility.")) {
                    HStack(spacing: 8) {
                        StatusDot(ok: state.accessibilityGranted)
                        if state.accessibilityGranted {
                            Text("OK").foregroundStyle(.secondary)
                        } else {
                            Button("Poproś") { state.requestAccessibility() }
                            Button("Ustawienia") { state.openAccessibilitySettings() }
                        }
                    }
                }
            }
            SettingsGroup("Dźwięk") {
                SettingRow(title: "Nagrywanie dźwięku systemowego",
                           subtitle: state.audioPermissionSubtitle) {
                    HStack(spacing: 8) {
                        if case .checking = state.audioPermission {
                            ProgressView().controlSize(.small)
                        } else {
                            StatusDot(ok: state.audioPermissionGranted)
                        }
                        if state.audioPermission.isGranted {
                            Text("OK").foregroundStyle(.secondary)
                            Button("Sprawdź") { state.checkAudioPermission(force: true) }
                        } else {
                            Button("Poproś") { state.checkAudioPermission(force: true) }
                            if state.audioPermissionGranted == false {
                                Button("Napraw zgodę") { state.repairAudioPermission() }
                            }
                            Button("Ustawienia") { state.openAudioCaptureSettings() }
                        }
                    }
                    .disabled({ if case .checking = state.audioPermission { return true }; return false }())
                }
            }
            SettingsGroup("Ekran wirtualny") {
                SettingRow(title: "Nagrywanie ekranu",
                           subtitle: state.screenCaptureGranted
                           ? L10n.text("Nadane – Mac może pokazać ekran wirtualny na Windowsie.", "Granted — the Mac can show its virtual display on Windows.")
                           : L10n.text("Potrzebne tylko dla ekranu wirtualnego. Po nadaniu zgody uruchom aplikację ponownie.", "Needed only for the virtual display. Relaunch the app after granting it.")) {
                    HStack(spacing: 8) {
                        StatusDot(ok: state.screenCaptureGranted ? true : nil)
                        if state.screenCaptureGranted {
                            Text("OK").foregroundStyle(.secondary)
                        } else {
                            Button("Poproś") { state.requestScreenCapture() }
                            Button("Ustawienia") { state.openScreenCaptureSettings() }
                        }
                    }
                }
            }
        }
        .onAppear { state.checkAudioPermission(force: false) }
    }
}
