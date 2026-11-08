import ImageIO
import SwiftUI

/// A Book's Cover at a 2:3 aspect ratio, decoded off the main thread. Shows a
/// neutral placeholder while loading, or when the Cover file is missing.
struct CoverView: View {
    let url: URL?

    @State private var image: CGImage?

    var body: some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else {
                    CoverPlaceholder()
                }
            }
            .clipShape(.rect(cornerRadius: 6))
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            .task(id: url) {
                guard let url else {
                    image = nil
                    return
                }
                image = await Self.decode(url)
            }
    }

    @concurrent private static func decode(_ url: URL) async -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(
            source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}

/// The neutral fill shown where a Cover is not available.
struct CoverPlaceholder: View {
    var body: some View {
        Rectangle().fill(.fill.tertiary)
    }
}
