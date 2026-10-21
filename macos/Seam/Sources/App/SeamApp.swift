import AppKit
import SwiftUI

@main
struct SeamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Dopiero przy budowaniu scen: tryby diagnostyczne z `init` kończą proces wcześniej i nie mogą
    /// uruchamiać serwera ani zmieniać autostartu.
    private var state: AppState { AppState.shared }

    init() {
        // Tryb diagnostyczny: sprawdza mechanizm autostartu i kończy działanie,
        // bez uruchamiania serwera ani interfejsu.
        if CommandLine.arguments.contains("--login-item-test") {
            LoginItem.runDiagnostics()
        }
        if CommandLine.arguments.contains("--display-selftest") {
            DisplaySelfTest.run()
        }
        // Diagnostyka: przechwytywanie dźwięku systemowego przez kilka sekund, jak podczas sesji
        // (np. do sprawdzenia, czy w tym czasie działa mikrofon).
        if let index = CommandLine.arguments.firstIndex(of: "--audio-tap-test") {
            let seconds = CommandLine.arguments.dropFirst(index + 1).first.flatMap(Double.init) ?? 6
            let tap = SystemAudioTap()
            do {
                try tap.start(muteLocal: CommandLine.arguments.contains("--mute"), bufferFrames: 256)
                print("tap działa: \(tap.format.map { "\($0.sampleRate) Hz, \($0.channels) kan." } ?? "?")")
                Thread.sleep(forTimeInterval: seconds)
                tap.stop()
                exit(0)
            } catch {
                print("tap: \(error.localizedDescription)")
                exit(1)
            }
        }
        if CommandLine.arguments.contains("--ui-preview") {
            UIPreview.run()
        }
    }

    var body: some Scene {
        Window("Seam", id: "main") {
            ContentView().environment(state)
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1180, height: 800)
        .commands { SettingsCommands() }

        MenuBarExtra {
            MenuBarView().environment(state)
        } label: {
            MenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Ikona w pasku menu jako osobny widok: każde odświeżenie etykiety to przerysowanie
/// paska menu przez WindowServer, więc zależy ona tylko od położenia kursora.
private struct MenuBarLabel: View {
    let state: AppState

    var body: some View {
        Image(systemName: state.cursorOnMac ? "cursorarrow.motionlines.click" : "cursorarrow.motionlines")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// true, gdy aplikację uruchomił system (element logowania / LaunchAgent),
    /// a nie użytkownik z Findera lub Docka.
    static var launchedAtLogin: Bool {
        if CommandLine.arguments.contains(LoginItem.loginArgument) { return true }
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let systemLaunch = Self.launchedAtLogin
            || (notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool) == false
        if systemLaunch && AppState.shared.settings.startHidden {
            // tylko ikona w pasku menu – bez okna i bez wybijania na wierzch
            NSApp.setActivationPolicy(.accessory)
            DispatchQueue.main.async {
                for window in NSApp.windows where window.canBecomeMain {
                    window.close()
                }
            }
            return
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Kliknięcie ikony w Docku / ponowne otwarcie przywraca politykę zwykłej aplikacji.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.setActivationPolicy(.regular)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.shutdown()
    }
}
