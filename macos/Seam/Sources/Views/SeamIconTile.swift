import SwiftUI

/// Silver artwork on a graphite gradient plate. A gradient mask lights the top of the
/// artwork and lets its base sink into the plate; the plate takes the accent when active.
struct SeamIconTile: View {
    let name: String
    var size: CGFloat = 30
    var active = false

    var body: some View {
        let plate = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        SeamArtwork(name: name)
            .overlay {
                LinearGradient(colors: [.white.opacity(0.45), .clear, .black.opacity(0.35)],
                               startPoint: .top, endPoint: .bottom)
                    .blendMode(.overlay)
                    .mask(SeamArtwork(name: name))
            }
            .padding(size * 0.1)
            .frame(width: size, height: size)
            .background {
                plate.fill(LinearGradient(colors: active ? DesignTokens.activePlate : DesignTokens.graphitePlate,
                                          startPoint: .top, endPoint: .bottom))
                plate.fill(EllipticalGradient(colors: [.white.opacity(0.16), .clear],
                                              center: UnitPoint(x: 0.5, y: 0), endRadiusFraction: 0.85))
            }
            .overlay {
                plate.strokeBorder(LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.03)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.35), radius: 2.5, y: 1.5)
            .accessibilityHidden(true)
    }
}
