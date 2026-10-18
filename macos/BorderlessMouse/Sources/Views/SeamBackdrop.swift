import AppKit
import SwiftUI

/// Graphite window backdrop: cool studio light from above, a faint accent glow
/// under the connection orb and fine grain so the dark gradients do not band.
/// Glows are laid out on the whole window (`canvasWidth`), so a column that draws its
/// own copy, like the sidebar, continues the same light instead of restarting it.
struct SeamBackdrop: View {
    var canvasWidth: CGFloat?

    var body: some View {
        if let canvasWidth {
            backdrop
                .frame(width: canvasWidth)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
        } else {
            backdrop
        }
    }

    private var backdrop: some View {
        ZStack {
            LinearGradient(colors: [DesignTokens.graphiteTop, DesignTokens.graphiteBottom],
                           startPoint: .top, endPoint: .bottom)
            EllipticalGradient(colors: [DesignTokens.studioLight.opacity(0.34), .clear],
                               center: UnitPoint(x: 0.6, y: -0.05), endRadiusFraction: 0.72)
            EllipticalGradient(colors: [DesignTokens.accent.opacity(0.17), .clear],
                               center: UnitPoint(x: 0.55, y: 1.02), endRadiusFraction: 0.42)
            EllipticalGradient(colors: [.black.opacity(0.4), .clear],
                               center: .bottomLeading, endRadiusFraction: 0.75)
            Image(nsImage: Self.grain)
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// One tile of monochrome noise, drawn once per launch at device-pixel size.
    private static let grain: NSImage = {
        let side = 128
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 2, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceWhite, bytesPerRow: side * 2, bitsPerPixel: 16),
              let pixels = rep.bitmapData else { return NSImage() }
        for i in 0..<(side * side) {
            let alpha = UInt8.random(in: 0...22)
            // Premultiplied: a white speck stores its alpha as the gray value, a dark one stores 0.
            pixels[i * 2] = Bool.random() ? alpha : 0
            pixels[i * 2 + 1] = alpha
        }
        let image = NSImage(size: NSSize(width: side / 2, height: side / 2))
        image.addRepresentation(rep)
        return image
    }()
}
