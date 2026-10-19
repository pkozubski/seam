import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 38, height: 38)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Seam").font(.headline)
                    Text(state.statusSummary.text)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let peer = state.peer {
                Label("\(peer.name) · \(peer.address)", systemImage: "display")
                    .font(.callout).foregroundStyle(.secondary)
            }
            VStack(spacing: 14) {
                QuickToggleRow(title: "Klawiatura i mysz", symbol: "keyboard", isOn: $state.settings.inputEnabled)
                QuickToggleRow(title: "Udostępniaj dźwięk", symbol: "speaker.wave.2", isOn: $state.settings.audioEnabled)
                QuickToggleRow(title: "Wycisz Maca podczas streamu", symbol: "speaker.slash", isOn: $state.settings.muteLocalAudio)
                QuickToggleRow(title: "Synchronizuj schowek", symbol: "doc.on.clipboard", isOn: $state.settings.clipboardSyncEnabled)
                Divider()
                QuickToggleRow(title: "Uruchamiaj przy logowaniu", symbol: "power", isOn: $state.settings.launchAtLogin)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.callout)
            .padding(16)
            .modifier(SurfaceStyle())

            HStack {
                Button("Otwórz aplikację", action: openMainWindow)
                    .modifier(NativeActionStyle(prominent: true))
                    .keyboardShortcut("o")
                Spacer()
                Menu {
                    if state.peer != nil {
                        Button("Rozłącz", action: state.disconnectPeer)
                    }
                    Button("Sprawdź aktualizacje…") {
                        state.checkForUpdates()
                        openMainWindow()
                    }
                    Divider()
                    Button("Zakończ") { NSApp.terminate(nil) }
                        .keyboardShortcut("q")
                } label: {
                    Label("Więcej", systemImage: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
