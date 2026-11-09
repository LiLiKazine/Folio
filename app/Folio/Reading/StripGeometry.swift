import CoreGraphics

/// Where every Page sits in the Vertical strip, worked out before any Page is decoded.
struct StripGeometry: Equatable, Sendable {
    /// Each Page's height in points, in reading order.
    let heights: [CGFloat]
    /// Each Page's top edge: the sum of the heights before it, so `tops[0]` is 0.
    let tops: [CGFloat]
    /// The height of the whole strip.
    let contentHeight: CGFloat

    /// Heights in points at `width` on a screen of `displayScale` pixels per point; a nil
    /// pixel size is a square of `width`. A pixel size with no area cannot give a height, so
    /// it is a square too. Each height is rounded to the nearest whole screen pixel, so every
    /// Page's top lies on the screen's pixel grid, where the scroll view comes to rest.
    init(pixelSizes: [CGSize?], width: CGFloat, displayScale: CGFloat) {
        let heightsInPixels = pixelSizes.map { size -> Int in
            guard let size, size.width > 0, size.height > 0 else {
                return Int((width * displayScale).rounded())
            }
            return Int((width * size.height / size.width * displayScale).rounded())
        }
        var tops: [CGFloat] = []
        var running = 0
        for height in heightsInPixels {
            tops.append(CGFloat(running) / displayScale)
            running += height
        }
        self.heights = heightsInPixels.map { CGFloat($0) / displayScale }
        self.tops = tops
        self.contentHeight = CGFloat(running) / displayScale
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

    /// The Pages to keep decoded when the strip is scrolled to `offset` with a visible area
    /// `viewportHeight` tall: every Page with any part on screen and one more on each side,
    /// so a screen of short Pages keeps more Pages than a screen showing one tall Page.
    /// Scrolled past either end, with nothing on screen, it is the nearest Page and its
    /// neighbour. Empty for an empty strip.
    func pagesToDecode(offset: CGFloat, viewportHeight: CGFloat) -> Range<Int> {
        guard !tops.isEmpty else { return 0..<0 }
        let last = tops.count - 1
        // The first Page whose bottom is below the top of the visible area.
        let firstOnScreen = min(firstIndex { tops[$0] + heights[$0] > offset }, last)
        // The last Page whose top is above the bottom of the visible area.
        let lastOnScreen = max(firstIndex { tops[$0] >= offset + viewportHeight } - 1, 0)
        return max(firstOnScreen - 1, 0)..<(min(lastOnScreen + 1, last) + 1)
    }

    /// The offset in this strip that keeps the reader at the same place as `offset` does in
    /// `previous` (the same Pages at another width or zoom): the same fraction of the way
    /// down the Page under the top of the screen. Pulled past either end, it is that end of
    /// the strip. A strip of other Pages has no same place, so it is 0.
    func offset(keepingPlaceOf offset: CGFloat, in previous: StripGeometry) -> CGFloat {
        guard !tops.isEmpty, previous.tops.count == tops.count, offset > 0 else { return 0 }
        guard offset < previous.contentHeight else { return contentHeight }
        // The Page under the top of the screen: the last one whose top is at or above it.
        let page = previous.firstIndex { previous.tops[$0] > offset } - 1
        let fraction = (offset - previous.tops[page]) / previous.heights[page]
        return tops[page] + fraction * heights[page]
    }

    /// The first Page for which `isPast` holds, or the Page count when none does. `isPast`
    /// must be false for every Page before some point and true from it on, as it is for
    /// tops and bottoms, which only grow down the strip.
    private func firstIndex(where isPast: (Int) -> Bool) -> Int {
        var low = 0
        var high = tops.count
        while low < high {
            let middle = (low + high) / 2
            if isPast(middle) { high = middle } else { low = middle + 1 }
        }
        return low
    }
}
