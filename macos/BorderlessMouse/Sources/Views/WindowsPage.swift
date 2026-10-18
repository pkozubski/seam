import SwiftUI

struct WindowsPage: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        SettingsPageLayout(title: "Okna", subtitle: "Monitor Windowsa staje się drugim ekranem Maca.") {
            if state.settings.displayEnabled && !state.screenCaptureGranted {
                PermissionBanner(title: "Brak uprawnienia Nagrywanie ekranu",
                                 message: "Potrzebne tylko tej funkcji. Po nadaniu uruchom aplikację ponownie.",
                                 grant: state.requestScreenCapture,
                                 openSettings: state.openScreenCaptureSettings)
            }
            FeatureHero(icon: "icon-windows", title: "Udostępniaj ekran wirtualny",
                        status: state.settings.displayEnabled ? state.displayStatusText : L10n.text("Wyłączone", "Off"),
                        ok: state.displayStreaming ? true : (state.displayError == nil ? nil : false),
                        isOn: $state.settings.displayEnabled) {
                if state.displayStreaming {
                    Button("Zatrzymaj") { state.stopDisplay() }
                }
            }
            SettingsGroup("Jak to działa") {
                step(1, "Włącz ekran wirtualny powyżej.")
                Divider()
                step(2, "Przeciągnij okno Maca w stronę Windowsa.")
                Divider()
                step(3, "Okno pojawi się na monitorze Windowsa. Stronę, po której stoi Mac, wybierasz w aplikacji na Windowsie, w zakładce Ekrany.")
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.callout.weight(.semibold).monospacedDigit())
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(.primary.opacity(0.08)))
                .accessibilityHidden(true)
            Text(LocalizedStringKey(text)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
