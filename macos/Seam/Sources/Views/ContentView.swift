import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showConnectionStatus = false
    @State private var selection: SidebarSection?
    @ObservedObject private var router = MainWindowRouter.shared
    @Environment(\.openSettings) private var openSettings

    init(initialSection: SidebarSection = .connection) {
        // Ustawienia mają osobne okno (scena Settings), nie są stroną paska bocznego.
        _selection = State(initialValue: initialSection == .settings ? .connection : initialSection)
    }

    /// Zakładka Okna ma zielone tło na całe okno, jak na Windowsie.
    private var greenWindow: Bool { selection == .windows }
    /// Zakładka Połączenie ma niebieskie tło pod grafiką hero.
    private var blueWindow: Bool { (selection ?? .connection) == .connection }
    /// Zakładka Klawiatura i mysz ma magentowe tło.
    private var magentaWindow: Bool { selection == .control }
    /// Zakładka Dźwięk ma fioletowe tło.
    private var violetWindow: Bool { selection == .audio }
    /// Zakładka Schowek ma bursztynowe tło.
    private var amberWindow: Bool { selection == .clipboard }
    private var orbAccent: ConnectionStatusButton.Accent {
        magentaWindow ? .magenta : violetWindow ? .violet : amberWindow ? .amber : greenWindow ? .leaf : .blue
    }

    var body: some View {
        // Własny układ kolumn zamiast NavigationSplitView: od macOS 26 system zamyka pasek boczny
        // w jaśniejszym szkle z cieniem i linią podziału, a Seam ma mieć jedno tło na całe okno.
        HStack(spacing: 0) {
            SidebarView(selection: $selection)
                .frame(width: 230)
                .frame(maxHeight: .infinity, alignment: .top)
                .overlay(alignment: .trailing) { SidebarSeparator().ignoresSafeArea() }

            DetailView(section: selection ?? .connection, openWindows: { selection = .windows },
                       openConnection: { selection = .connection })
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .modifier(SoftToolbarEdge())
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: greenWindow)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: blueWindow)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: magentaWindow)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: violetWindow)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: amberWindow)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .modifier(HiddenToolbarTitle())
        .background {
            ZStack {
                SeamBackdrop()
                ConnectionBackdrop().opacity(blueWindow ? 1 : 0)
                ControlBackdrop().opacity(magentaWindow ? 1 : 0)
                AudioBackdrop().opacity(violetWindow ? 1 : 0)
                ClipboardBackdrop().opacity(amberWindow ? 1 : 0)
                WindowsBackdrop().opacity(greenWindow ? 1 : 0)
            }
            .ignoresSafeArea()
        }
        .frame(minWidth: 980, idealWidth: 1180, minHeight: 680, idealHeight: 800)
        .background {
            ConnectionStatusAttachment(state: state, accent: orbAccent) { showConnectionStatus = true }
        }
        .sheet(isPresented: $showConnectionStatus) { ConnectionDetails().environment(state) }
        .onAppear { SettingsNavigation.shared.opener = { openSettings() } }
        // Okno Ustawień prosi o stronę okna głównego (Uprawnienia, Dziennik).
        .onReceive(router.$requested.compactMap { $0 }) { section in
            selection = section
            router.requested = nil
        }
        .preferredColorScheme(.dark)
        .tint(DesignTokens.accent)
        .sheet(isPresented: Binding(
            get: { !state.settings.hasCompletedOnboarding },
            set: { presented in if !presented { state.completeOnboarding() } }
        )) {
            OnboardingView()
                .environment(state)
                .interactiveDismissDisabled()
        }
    }
}

/// Bez kolumn split view tytuł strony stanąłby nad paskiem bocznym, obok świateł okna;
/// strony mają własne nagłówki, a tytuł zostaje tylko jako nazwa okna (menu Okno, Mission Control).
private struct HiddenToolbarTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}

/// Content scrolling under the transparent toolbar fades out instead of meeting a hard band.
private struct SoftToolbarEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}
