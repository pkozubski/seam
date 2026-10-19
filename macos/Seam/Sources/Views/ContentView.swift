import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showConnectionStatus = false
    @State private var selection: SidebarSection?
    @ObservedObject private var settingsNavigation = SettingsNavigation.shared

    init(initialSection: SidebarSection = .connection) {
        // Settings is no longer a page of the main sidebar; it takes over the window.
        if initialSection == .settings { SettingsNavigation.shared.present() }
        _selection = State(initialValue: initialSection == .settings ? .connection : initialSection)
    }

    private var slide: Animation { SettingsChrome.slide(reduceMotion: reduceMotion) }
    private var compactSidebar: Bool { selection == .windows && !settingsNavigation.isPresented }

    var body: some View {
        // Własny układ kolumn zamiast NavigationSplitView: od macOS 26 system zamyka pasek boczny
        // w jaśniejszym szkle z cieniem i linią podziału, a Seam ma mieć jedno tło na całe okno.
        HStack(spacing: 0) {
            ZStack {
                if settingsNavigation.isPresented {
                    SettingsSidebar(navigation: settingsNavigation)
                        .transition(.offset(x: -16).combined(with: .opacity))
                } else if compactSidebar {
                    WindowsSidebar(selection: $selection)
                } else {
                    SidebarView(selection: $selection)
                        .transition(.offset(x: -16).combined(with: .opacity))
                }
            }
            .animation(slide, value: settingsNavigation.isPresented)
            .frame(width: compactSidebar ? 76 : 230)
            .frame(maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .trailing) { SidebarSeparator().ignoresSafeArea() }

            ZStack {
                if settingsNavigation.isPresented {
                    SettingsDetail(navigation: settingsNavigation)
                        .transition(.offset(x: 24).combined(with: .opacity))
                } else {
                    DetailView(section: selection ?? .connection, openWindows: { selection = .windows },
                               openConnection: { selection = .connection })
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: selection)
                        .transition(.offset(x: 24).combined(with: .opacity))
                }
            }
            .animation(slide, value: settingsNavigation.isPresented)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(SoftToolbarEdge())
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: compactSidebar)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .modifier(HiddenToolbarTitle())
        .background {
            ZStack {
                SeamBackdrop()
                WindowsBackdrop().opacity(compactSidebar ? 1 : 0)
            }
            .ignoresSafeArea()
        }
        .frame(minWidth: 980, idealWidth: 1180, minHeight: 680, idealHeight: 800)
        .background {
            if !compactSidebar {
                ConnectionStatusAttachment(state: state) { showConnectionStatus = true }
            }
        }
        .sheet(isPresented: $showConnectionStatus) { ConnectionDetails().environmentObject(state) }
        .preferredColorScheme(.dark)
        .tint(DesignTokens.accent)
        .sheet(isPresented: Binding(
            get: { !state.settings.hasCompletedOnboarding },
            set: { presented in if !presented { state.completeOnboarding() } }
        )) {
            OnboardingView()
                .environmentObject(state)
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
