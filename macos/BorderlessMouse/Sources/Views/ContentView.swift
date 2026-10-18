import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showConnectionStatus = false
    @State private var selection: SidebarSection?

    init(initialSection: SidebarSection = .connection) {
        _selection = State(initialValue: initialSection)
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            DetailView(section: selection ?? .connection, openWindows: { selection = .windows })
                .background(DesignTokens.canvas)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: selection)
        }
        .frame(minWidth: 980, idealWidth: 1180, minHeight: 680, idealHeight: 800)
        .background(ConnectionStatusAttachment(state: state) { showConnectionStatus = true })
        .sheet(isPresented: $showConnectionStatus) { ConnectionDetails().environmentObject(state) }
        .preferredColorScheme(.dark)
        .tint(Color(red: 0.57, green: 0.68, blue: 0.55))
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
