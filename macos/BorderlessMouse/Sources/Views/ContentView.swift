import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showConnectionStatus = false
    @State private var selection: SidebarSection?
    @State private var canvasWidth: CGFloat = 1180

    init(initialSection: SidebarSection = .connection) {
        _selection = State(initialValue: initialSection)
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .background {
                    SeamBackdrop(canvasWidth: canvasWidth)
                        .overlay(Color.black.opacity(0.24))
                        .overlay(alignment: .trailing) { Color.white.opacity(0.06).frame(width: 0.5) }
                        .ignoresSafeArea()
                }
        } detail: {
            DetailView(section: selection ?? .connection, openWindows: { selection = .windows })
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: selection)
                .toolbarBackground(.hidden, for: .windowToolbar)
                .modifier(SoftToolbarEdge())
        }
        .background { SeamBackdrop().ignoresSafeArea() }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { canvasWidth = $0 }
        .frame(minWidth: 980, idealWidth: 1180, minHeight: 680, idealHeight: 800)
        .background(ConnectionStatusAttachment(state: state) { showConnectionStatus = true })
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
