import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showConnectionStatus = false
    @State private var selection: SidebarSection?
    @State private var canvasWidth: CGFloat = 1180
    @ObservedObject private var settingsNavigation = SettingsNavigation.shared

    init(initialSection: SidebarSection = .connection) {
        // Settings is no longer a page of the main sidebar; it takes over the window.
        if initialSection == .settings { SettingsNavigation.shared.present() }
        _selection = State(initialValue: initialSection == .settings ? .connection : initialSection)
    }

    private var slide: Animation { SettingsChrome.slide(reduceMotion: reduceMotion) }
    private var compactSidebar: Bool { selection == .windows && !settingsNavigation.isPresented }

    var body: some View {
        NavigationSplitView {
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
            .navigationSplitViewColumnWidth(min: compactSidebar ? 76 : 215,
                                            ideal: compactSidebar ? 76 : 230,
                                            max: compactSidebar ? 76 : 270)
            .background {
                SeamBackdrop(canvasWidth: canvasWidth)
                    .overlay(Color.black.opacity(0.24))
                    .overlay(alignment: .trailing) { Color.white.opacity(0.06).frame(width: 0.5) }
                    .ignoresSafeArea()
            }
        } detail: {
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
            .toolbarBackground(.hidden, for: .windowToolbar)
            .modifier(SoftToolbarEdge())
        }
        .background { SeamBackdrop().ignoresSafeArea() }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { canvasWidth = $0 }
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
