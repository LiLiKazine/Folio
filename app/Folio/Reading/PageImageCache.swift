import CoreGraphics
import Foundation

/// Holds the decoded Pages of one open Book: the Page being read and one on each
/// side, so turning a Page shows it at once and a 500-Page Book never holds more than
/// three full-window images.
actor PageImageCache {
    /// What decoding one Page produced. A Page that cannot be decoded is held as
    /// `nil`, so it is not retried every time the reader scrolls past it.
    private struct Decoded {
        let image: CGImage?
    }

    private let urls: [URL]
    private let maxPixelSize: Int
    private var held: [Int: Decoded] = [:]
    /// How many decodes have run; lets tests see what the cache kept and what it dropped.
    private(set) var decodeCount = 0

    /// `urls` are the Book's Page files in reading order; `maxPixelSize` is the longer
    /// side of the window in pixels.
    init(urls: [URL], maxPixelSize: Int) {
        self.urls = urls
        self.maxPixelSize = maxPixelSize
    }

    /// The Page at `index`, decoded now if the cache does not hold it; nil when the
    /// index is outside the Book or the Page cannot be decoded.
    func image(at index: Int) -> CGImage? {
        guard urls.indices.contains(index) else { return nil }
        if let decoded = held[index] { return decoded.image }
        let decoded = Decoded(image: PageImage.decode(url: urls[index], maxPixelSize: maxPixelSize))
        decodeCount += 1
        held[index] = decoded
        return decoded.image
    }

    /// Decodes the Pages on each side of `index` and drops every Page more than one
    /// away from it.
    func prefetch(around index: Int) {
        let window = (index - 1)...(index + 1)
        held = held.filter { window.contains($0.key) }
        for neighbour in [index - 1, index + 1] where urls.indices.contains(neighbour) {
            _ = image(at: neighbour)
        }
    }
}
