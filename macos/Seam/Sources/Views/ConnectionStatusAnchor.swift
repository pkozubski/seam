import AppKit
import SwiftUI

final class ConnectionStatusAnchor: NSView {
    private var panel: NSPanel?
    private var observers: [NSObjectProtocol] = []
    private var state: AppState?
    private var action: (() -> Void)?
    private var accent: ConnectionStatusButton.Accent = .blue

    func update(state: AppState, accent: ConnectionStatusButton.Accent, action: @escaping () -> Void) {
        self.state = state
        self.accent = accent
        self.action = action
        attachIfNeeded()
        if let hosting = panel?.contentView as? NSHostingView<ConnectionStatusButton> {
            hosting.rootView = ConnectionStatusButton(state: state, accent: accent, action: action)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        detach()
        attachIfNeeded()
    }

    private func attachIfNeeded() {
        guard panel == nil, let parent = window, let state, let action else { return }
        let side = ConnectionStatusButton.panelSide
        let child = NSPanel(contentRect: NSRect(x: 0, y: 0, width: side, height: side),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        child.identifier = NSUserInterfaceItemIdentifier("seam.connection-status")
        child.isOpaque = false
        child.backgroundColor = .clear
        child.hasShadow = false
        child.hidesOnDeactivate = false
        child.isReleasedWhenClosed = false
        child.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        child.contentView = NSHostingView(rootView: ConnectionStatusButton(state: state, accent: accent, action: action))
        panel = child
        parent.addChildWindow(child, ordered: .above)
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.positionPanel() }
            })
        }
        positionPanel()
    }

    private func positionPanel() {
        guard let parent = window, let panel else { return }
        // Keep the entire control reachable when the window touches the Dock / screen edge.
        let bottom = parent.screen?.visibleFrame.minY ?? parent.frame.minY - 48
        // Dolna krawędź kuli 34 pt pod oknem; reszta panelu to miejsce na poświatę.
        let inset = ConnectionStatusButton.glowInset
        let y = max(parent.frame.minY - 34, bottom + 14) - inset
        panel.setFrameOrigin(NSPoint(x: parent.frame.midX - ConnectionStatusButton.panelSide / 2, y: y))
    }

    func detach() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.close()
        }
        panel = nil
    }
}
