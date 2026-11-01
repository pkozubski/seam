import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var state = state
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
                QuickToggleRow(title: "Keyboard and mouse", symbol: "keyboard", isOn: $state.settings.inputEnabled)
                // Dźwięk to Seam Pro: bez niego przełącznik jest wyłączony, a zapisana wartość czeka na zakup.
                QuickToggleRow(title: "Share audio", symbol: "speaker.wave.2",
                               isOn: state.proUnlocked ? $state.settings.audioEnabled : .constant(false))
                    .disabled(!state.proUnlocked)
                QuickToggleRow(title: "Mute Mac while streaming", symbol: "speaker.slash", isOn: $state.settings.muteLocalAudio)
                QuickToggleRow(title: "Sync clipboard", symbol: "doc.on.clipboard", isOn: $state.settings.clipboardSyncEnabled)
                Divider()
                QuickToggleRow(title: "Launch at login", symbol: "power", isOn: $state.settings.launchAtLogin)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.callout)
            .padding(16)
            .modifier(SurfaceStyle())

            HStack {
                Button("Open app", action: openMainWindow)
                    .modifier(NativeActionStyle(prominent: true))
                    .keyboardShortcut("o")
                Spacer()
                Menu {
                    if state.peer != nil {
                        Button("Disconnect", action: state.disconnectPeer)
                    }
                    Button("Check for updates…") {
                        state.checkForUpdates()
                        openMainWindow()
                    }
                    Divider()
                    Button("Quit") { NSApp.terminate(nil) }
                        .keyboardShortcut("q")
                } label: {
                    Label("More", systemImage: "ellipsis")
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
