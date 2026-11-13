import SwiftUI

struct ConnectionOverview: View {
    @Environment(AppState.self) private var state
    var openWindows: () -> Void = {}
    private var connected: Bool { state.peer != nil }

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 22) {
            Text(L10n.text("Two computers.\nOne space.", pl: "Dwa komputery.\nJedna przestrzeń."))
                .font(.system(size: 36, weight: .regular)).tracking(-1)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(state.settings.deviceName)  ↔  \(state.peer?.name ?? L10n.text("Your PC", pl: "Twój PC"))")
                .font(.system(size: 16)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 22) {
                QuickToggleRow(title: L10n.text("Mouse & keyboard", pl: "Mysz i klawiatura"), symbol: "computermouse", isOn: $state.settings.inputEnabled,
                               tile: "tile-control")
                QuickToggleRow(title: L10n.text("Audio from Mac", pl: "Dźwięk z Maca"), symbol: "speaker.wave.2", isOn: $state.settings.audioEnabled,
                               tile: "tile-audio")
                QuickToggleRow(title: L10n.text("Shared clipboard", pl: "Wspólny schowek"), symbol: "clipboard", isOn: $state.settings.clipboardSyncEnabled,
                               tile: "tile-clipboard")
                Button(action: openWindows) {
                    HStack(spacing: 10) {
                        ConnectionTile(name: "tile-windows")
                        Text(L10n.text("Move a window", pl: "Przenieś okno"))
                    }.font(.body).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help(L10n.text("Open window sharing settings", pl: "Otwórz ustawienia przenoszenia okien"))
            }.padding(.top, 20)
            if let error = state.listenError {
                Text(error).font(.callout).foregroundStyle(.orange)
            } else if !state.accessibilityGranted {
                Button(L10n.text("Allow control in macOS", pl: "Zezwól na sterowanie w macOS"), action: state.openAccessibilitySettings)
            }
        }
    }
}
