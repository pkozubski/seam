import AppKit
import SwiftUI

/// Renderowanie interfejsu do pliku PNG bez uruchamiania serwera, audio ani
/// uprawnień – diagnostyka wyglądu (`--ui-preview <plik.png>`).
/// Odpowiednik `--screenshot` w wersji Windows.
///
/// Okno jest pokazywane na chwilę na ekranie: pasek boczny (materiał) i pasek
/// narzędzi renderuje dopiero kompozytor, więc zrzut z NSHostingView poza oknem
/// byłby niepełny. Sekcję paska bocznego wybiera `--ui-section <connection|permissions|control|settings|log>`.
@MainActor
enum UIPreview {
    static func run() -> Never {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--ui-preview"), idx + 1 < args.count else {
            FileHandle.standardError.write(Data("użycie: --ui-preview <plik.png>\n".utf8))
            exit(2)
        }
        let path = args[idx + 1]
        let state = AppState.demo()
        if args.contains("--ui-full-windows") {
            // NSHostingView includes AppKit-backed controls that ImageRenderer omits.
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            let host = NSHostingView(rootView: WindowsPage(fullPreview: true)
                .environment(state).environment(\.colorScheme, .dark).tint(DesignTokens.accent))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1100, height: 1800),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            host.setFrameSize(host.fittingSize)
            for _ in 0..<3 { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(3) }
            host.cacheDisplay(in: host.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { exit(3) }
            do { try png.write(to: URL(fileURLWithPath: path)) } catch { exit(3) }
            print("zapisano \(path) (\(rep.pixelsWide)×\(rep.pixelsHigh) px)")
            exit(0)
        }
        // `--ui-settings <general|updates|advanced>` opens settings on that page;
        // `--ui-update <available|downloading|installing|updated|failed>` fakes the updater.
        if let i = args.firstIndex(of: "--ui-settings"), i + 1 < args.count, let pane = SettingsPane(rawValue: args[i + 1]) {
            SettingsNavigation.shared.present(pane)
        }
        let updateIndex = args.firstIndex(of: "--ui-update")
        state.updater.showPreview(updateIndex.flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? "uptodate")
        var section = SidebarSection.connection
        if let s = args.firstIndex(of: "--ui-section"), s + 1 < args.count, let parsed = SidebarSection(rawValue: args[s + 1]) {
            section = parsed
        }
        let root = Group {
            if args.contains("--ui-menu") {
                MenuBarView()
            } else if args.contains("--ui-onboarding") {
                OnboardingView()
            } else {
                ContentView(initialSection: section)
            }
        }.environment(state)
        let size: CGSize
        if args.contains("--ui-menu") {
            size = CGSize(width: 340, height: 420)
        } else if args.contains("--ui-onboarding") {
            size = CGSize(width: 580, height: 460)
        } else {
            size = args.contains("--ui-compact") ? CGSize(width: 980, height: 680) : CGSize(width: 1180, height: 800)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Seam"
        window.toolbarStyle = .unified
        // The app's Window scene gets this from `.toolbarBackground(.hidden, for: .windowToolbar)`;
        // a hand-made NSWindow does not, so mirror it to keep the backdrop under the title bar.
        window.titlebarAppearsTransparent = true
        if args.contains("--ui-light") { window.appearance = NSAppearance(named: .aqua) }
        if args.contains("--ui-dark") { window.appearance = NSAppearance(named: .darkAqua) }
        window.contentView = NSHostingView(rootView: root)
        window.center()
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)

        if args.contains("--ui-interactive") {
            app.run()
            exit(0)
        }

        for _ in 0..<5 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        }

        // Capture the attached status panel too: it intentionally extends beyond the parent.
        let captureWindows = (window.childWindows ?? []).filter { $0.isVisible } + [window]
        let windowIDs = CFArrayCreateMutable(nil, 0, nil)!
        for captured in captureWindows {
            CFArrayAppendValue(windowIDs, UnsafeRawPointer(bitPattern: captured.windowNumber))
        }
        guard let cg = CGImage(windowListFromArrayScreenBounds: .null, windowArray: windowIDs, imageOption: [.bestResolution, .boundsIgnoreFraming]) else {
            FileHandle.standardError.write(Data("nie udało się zrzucić okna\n".utf8))
            exit(3)
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { exit(3) }
        do {
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            FileHandle.standardError.write(Data("Nie można zapisać podglądu: \(error)\n".utf8))
            exit(3)
        }
        print("zapisano \(path) (\(cg.width)×\(cg.height) px)")
        exit(0)
    }
}
