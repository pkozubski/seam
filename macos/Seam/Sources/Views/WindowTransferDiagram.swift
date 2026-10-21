import SwiftUI

/// The window follows the negotiated edge, including vertically arranged screens.
/// `progress` is an illustration position, never a request to move a real window.
struct WindowTransferDiagram: View {
    var edge: ScreenEdge = .right
    var progress: CGFloat = 0.5
    var compact = false
    var showWindow = true
    var showHints = false

    private var vertical: Bool { edge == .top || edge == .bottom }
    private var reversed: Bool { edge == .left || edge == .top }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let screenWidth = vertical ? size.width * 0.64 : (size.width - 4) / 2
            let screenHeight = vertical ? (size.height - 4) / 2 : size.height
            let first = CGPoint(x: vertical ? size.width / 2 : screenWidth / 2,
                                y: vertical ? screenHeight / 2 : size.height / 2)
            let second = CGPoint(x: vertical ? size.width / 2 : size.width - screenWidth / 2,
                                 y: vertical ? size.height - screenHeight / 2 : size.height / 2)
            let source = reversed ? second : first
            let destination = reversed ? first : second
            let point = CGPoint(x: source.x + (destination.x - source.x) * progress,
                                y: source.y + (destination.y - source.y) * progress)
            let preferredWidth = vertical ? screenWidth * 0.64 : size.width * 0.34
            let windowHeight = min(screenHeight * 0.72, preferredWidth * 0.65)
            let windowWidth = windowHeight / 0.65

            ZStack {
                WindowDemoDesktop(isMac: !reversed)
                    .frame(width: screenWidth, height: screenHeight).position(first)
                WindowDemoDesktop(isMac: reversed)
                    .frame(width: screenWidth, height: screenHeight).position(second)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(red: 0.65, green: 0.87, blue: 0.65))
                    .frame(width: vertical ? screenWidth : 3, height: vertical ? 3 : screenHeight)
                    .position(x: size.width / 2, y: size.height / 2)
                if showWindow {
                    if showHints {
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(.white.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            .frame(width: windowWidth, height: windowHeight).position(source)
                    }
                    WindowDemoDocument(compact: compact)
                        .frame(width: windowWidth, height: windowHeight)
                        .position(point)
                    if showHints {
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                            .position(x: point.x - windowWidth * 0.18, y: point.y - windowHeight / 2 + 14)
                        Image(systemName: arrow)
                            .font(.system(size: 25, weight: .medium))
                            .foregroundStyle(Color(red: 0.73, green: 0.94, blue: 0.71))
                            .position(x: point.x + (vertical ? windowWidth / 2 + 20 : 25),
                                      y: point.y - (vertical ? 0 : windowHeight / 2 + 18))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var arrow: String {
        switch edge {
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        case .top: return "arrow.up"
        case .bottom: return "arrow.down"
        }
    }
}
