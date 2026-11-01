import SwiftUI

struct WindowDemoDesktop: View {
    let isMac: Bool

    var body: some View {
        GeometryReader { geometry in
            SeamArtwork(name: isMac ? "window-desktop-mac" : "window-desktop-pc", contentMode: .fill)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .background(Color(red: 0.02, green: 0.14, blue: 0.17))
                .overlay(alignment: .topLeading) {
                    Text(isMac ? "Mac" : "Windows")
                        .font(.caption2.weight(.medium)).foregroundStyle(.white.opacity(0.8)).padding(8)
                }
                .overlay(alignment: .bottom) {
                    HStack(spacing: 5) {
                        ForEach(0..<6) { index in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.white.opacity(index == 1 ? 0.8 : 0.3))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(5)
                    .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 5))
                    .padding(.bottom, 7)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.25), lineWidth: 1) }
        }
        .accessibilityHidden(true)
    }
}
