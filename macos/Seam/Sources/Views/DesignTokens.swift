import SwiftUI

/// Native colors resolve in both appearances and follow the user's accent color.
enum DesignTokens {
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let accent = Color(red: 0.57, green: 0.68, blue: 0.55)
    static let graphiteTop = Color(red: 0.135, green: 0.143, blue: 0.155)
    static let graphiteBottom = Color(red: 0.078, green: 0.083, blue: 0.092)
    static let studioLight = Color(red: 0.47, green: 0.51, blue: 0.57)
    static let graphitePlate = [Color(red: 0.35, green: 0.365, blue: 0.4), Color(red: 0.12, green: 0.127, blue: 0.142)]
    static let activePlate = [Color(red: 0.43, green: 0.52, blue: 0.42), Color(red: 0.17, green: 0.22, blue: 0.175)]
    static let cornerRadius: CGFloat = 16
    static let pageInset: CGFloat = 28
    static let sectionSpacing: CGFloat = 24
    static let contentWidth: CGFloat = 760
    static let interaction = Animation.spring(response: 0.28, dampingFraction: 0.86)
}
