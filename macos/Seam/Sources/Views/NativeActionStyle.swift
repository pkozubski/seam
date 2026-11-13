import SwiftUI

/// Let macOS render interactive glass, including its keyboard and hover states.
struct NativeActionStyle: ViewModifier {
    var prominent = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}
