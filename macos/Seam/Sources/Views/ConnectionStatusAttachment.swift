import AppKit
import SwiftUI

/// A child panel can cross the native window boundary without replacing macOS chrome.
struct ConnectionStatusAttachment: NSViewRepresentable {
    let state: AppState
    let action: () -> Void

    func makeNSView(context: Context) -> ConnectionStatusAnchor { ConnectionStatusAnchor() }
    func updateNSView(_ view: ConnectionStatusAnchor, context: Context) {
        view.update(state: state, action: action)
    }
    static func dismantleNSView(_ view: ConnectionStatusAnchor, coordinator: ()) { view.detach() }
}
