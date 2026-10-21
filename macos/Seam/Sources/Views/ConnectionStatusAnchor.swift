import AppKit
import SwiftUI

final class ConnectionStatusAnchor: NSView {
    private var panel: NSPanel?
    private var observers: [NSObjectProtocol] = []
    private var state: AppState?
    private var action: (() -> Void)?

    func update(state: AppState, action: @escaping () -> Void) {
        self.state = state
        self.action = action
        attachIfNeeded()
        if let hosting = panel?.contentView as? NSHostingView<ConnectionStatusButton> {
            hosting.rootView = ConnectionStatusButton(state: state, action: action)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        detach()
        attachIfNeeded()
    }

    private func attachIfNeeded() {
        guard panel == nil, let parent = window, let state, let action else { return }
        let child = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 126, height: 126),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        child.identifier = NSUserInterfaceItemIdentifier("seam.connection-status")
        child.isOpaque = false
        child.backgroundColor = .clear
        child.hasShadow = false
        child.hidesOnDeactivate = false
        child.isReleasedWhenClosed = false
        child.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        child.contentView = NSHostingView(rootView: ConnectionStatusButton(state: state, action: action))
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
        let y = max(parent.frame.minY - 48, bottom)
        panel.setFrameOrigin(NSPoint(x: parent.frame.midX - 63, y: y))
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
