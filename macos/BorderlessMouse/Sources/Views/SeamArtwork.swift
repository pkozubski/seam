import SwiftUI

/// Shared artwork is bundled by both platform builds and decoded once per asset.
struct SeamArtwork: View {
    let name: String
    private static let cache = NSCache<NSString, NSImage>()

    private var artwork: NSImage? {
        if let cached = Self.cache.object(forKey: name as NSString) { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        Self.cache.setObject(image, forKey: name as NSString)
        return image
    }

    var body: some View {
        if let artwork {
            Image(nsImage: artwork).resizable().interpolation(.high).scaledToFit()
        }
    }
}
