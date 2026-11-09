import CoreGraphics

/// Where every Page sits in the Vertical strip, worked out before any Page is decoded.
struct StripGeometry: Equatable, Sendable {
    /// Each Page's height in points, in reading order.
    let heights: [CGFloat]
    /// Each Page's top edge: the sum of the heights before it, so `tops[0]` is 0.
    let tops: [CGFloat]
    /// The height of the whole strip.
    let contentHeight: CGFloat

    /// Heights in points at `width`; a nil pixel size is a square of `width`. A pixel size
    /// with no area cannot give a height, so it is a square too.
    init(pixelSizes: [CGSize?], width: CGFloat) {
        let heights = pixelSizes.map { size -> CGFloat in
            guard let size, size.width > 0, size.height > 0 else { return width }
            return width * size.height / size.width
        }
        var tops: [CGFloat] = []
        var running: CGFloat = 0
        for height in heights {
            tops.append(running)
            running += height
        }
        self.heights = heights
        self.tops = tops
        self.contentHeight = running
    }

    /// The Page at the top of the screen: the last Page whose top is at or above `offset`.
    /// At the very end (`offset + viewportHeight >= contentHeight`) it is the last Page, so
    /// a short last Page can be reached. `offset <= 0` is the first Page, which keeps a strip
    /// shorter than the screen on its first Page. An empty strip is Page 0.
    func pageAtTop(offset: CGFloat, viewportHeight: CGFloat) -> Int {
        guard !tops.isEmpty, offset > 0 else { return 0 }
        if offset + viewportHeight >= contentHeight { return tops.count - 1 }
        // Binary search for the first top beyond the offset; the Page before it is the answer.
        var low = 0
        var high = tops.count
        while low < high {
            let middle = (low + high) / 2
            if tops[middle] <= offset { low = middle + 1 } else { high = middle }
        }
        return max(low - 1, 0)
    }
}
