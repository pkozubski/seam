import SwiftUI

/// Native colors resolve in both appearances and follow the user's accent color.
enum DesignTokens {
    static let canvas = Color(red: 0.115, green: 0.122, blue: 0.13)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let cornerRadius: CGFloat = 16
    static let pageInset: CGFloat = 28
    static let sectionSpacing: CGFloat = 24
    static let contentWidth: CGFloat = 760
    static let interaction = Animation.spring(response: 0.28, dampingFraction: 0.86)
}
