import SwiftUI

struct ConnectionOverview: View {
    @EnvironmentObject private var state: AppState
    var openWindows: () -> Void = {}
    private var connected: Bool { state.peer != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(L10n.text("Dwa komputery.\nJedna przestrzeń.", "Two computers.\nOne space."))
                .font(.system(size: 36, weight: .regular)).tracking(-1)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(state.settings.deviceName)  ↔  \(state.peer?.name ?? L10n.text("Twój PC", "Your PC"))")
                .font(.system(size: 16)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 22) {
                QuickToggleRow(title: L10n.text("Mysz i klawiatura", "Mouse & keyboard"), symbol: "computermouse", isOn: $state.settings.inputEnabled)
                QuickToggleRow(title: L10n.text("Dźwięk z Maca", "Audio from Mac"), symbol: "speaker.wave.2", isOn: $state.settings.audioEnabled)
                QuickToggleRow(title: L10n.text("Wspólny schowek", "Shared clipboard"), symbol: "clipboard", isOn: $state.settings.clipboardSyncEnabled)
                Button(action: openWindows) {
                    HStack(spacing: 10) {
                        SeamIconTile(name: "icon-windows", size: 32)
                        Text(L10n.text("Przenieś okno", "Move a window"))
                    }.font(.body).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help(L10n.text("Otwórz ustawienia przenoszenia okien", "Open window sharing settings"))
            }.padding(.top, 20)
            if let error = state.listenError {
                Text(error).font(.callout).foregroundStyle(.orange)
            } else if !state.accessibilityGranted {
                Button(L10n.text("Zezwól na sterowanie w macOS", "Allow control in macOS"), action: state.openAccessibilitySettings)
            }
        }
    }
}
