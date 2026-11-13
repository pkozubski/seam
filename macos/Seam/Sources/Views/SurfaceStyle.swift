import SwiftUI

struct SurfaceStyle: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).fill(DesignTokens.surface)
                } else {
                    RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).fill(.regularMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                    .strokeBorder(.primary.opacity(contrast == .increased ? 0.35 : 0.07), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
    }
}
