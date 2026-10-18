import SwiftUI

/// Tonal panels keep the guide readable over the feature's teal atmosphere.
struct WindowGuideSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .padding(24)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(reduceTransparency
                          ? Color(red: 0.10, green: 0.22, blue: 0.23)
                          : Color.white.opacity(0.065))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.white.opacity(contrast == .increased ? 0.5 : 0.13), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}
