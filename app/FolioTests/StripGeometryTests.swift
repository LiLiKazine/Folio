import CoreGraphics
import Testing

@testable import Folio

@Suite("StripGeometry")
struct StripGeometryTests {
    @Test("heights fit each Page to the width; a Page with no pixel size is a square")
    func heightsAndTops() {
        let geometry = StripGeometry(
            pixelSizes: [CGSize(width: 800, height: 1200), nil, CGSize(width: 800, height: 400)],
            width: 400, displayScale: 1)

        #expect(geometry.heights == [600, 400, 200])
        #expect(geometry.tops == [0, 600, 1000])
        #expect(geometry.contentHeight == 1200)
    }

    @Test("a Page whose pixel size has no area is a square, not a division by zero")
    func degeneratePixelSize() {
        let geometry = StripGeometry(
            pixelSizes: [CGSize(width: 0, height: 10), CGSize(width: 10, height: 0)], width: 300,
            displayScale: 1)

        #expect(geometry.heights == [300, 300])
    }

    @Test(
        "the Page at the top is the last Page whose top has reached the screen top, and the last Page at the end",
        arguments: [
            (-20, 0), (0, 0), (599, 0), (600, 1), (699, 1), (700, 2), (999, 2), (1000, 2),
        ] as [(CGFloat, Int)])
    func pageAtTop(offset: CGFloat, expected: Int) {
        // Heights at width 400 are [600, 400, 200].
        let geometry = StripGeometry(
            pixelSizes: [
                CGSize(width: 100, height: 150), CGSize(width: 100, height: 100),
                CGSize(width: 100, height: 50),
            ], width: 400, displayScale: 1)
        #expect(geometry.heights == [600, 400, 200])

        #expect(geometry.pageAtTop(offset: offset, viewportHeight: 500) == expected)
    }

    @Test("a strip shorter than the screen stays on its first Page until it is scrolled")
    func shortPages() {
        let geometry = StripGeometry(
            pixelSizes: Array(repeating: CGSize(width: 100, height: 100), count: 4), width: 100,
            displayScale: 1)

        #expect(geometry.pageAtTop(offset: 0, viewportHeight: 500) == 0)
        #expect(geometry.pageAtTop(offset: 1, viewportHeight: 500) == 3)
    }

    @Test("one Page is always Page 0, and an empty strip is Page 0")
    func onePageAndEmpty() {
        let one = StripGeometry(
            pixelSizes: [CGSize(width: 100, height: 100)], width: 100, displayScale: 1)
        for offset: CGFloat in [-10, 0, 50] {
            #expect(one.pageAtTop(offset: offset, viewportHeight: 500) == 0)
        }

        let empty = StripGeometry(pixelSizes: [], width: 100, displayScale: 1)
        #expect(empty.heights.isEmpty)
        #expect(empty.contentHeight == 0)
        #expect(empty.pageAtTop(offset: 100, viewportHeight: 500) == 0)
    }

    /// Six Pages 300 points tall: tops 0, 300, 600, 900, 1200, 1500; the strip is 1800.
    private let sixPages = StripGeometry(
        pixelSizes: Array(repeating: CGSize(width: 100, height: 300), count: 6), width: 100,
        displayScale: 1)

    @Test(
        "the Pages kept decoded are every Page with any part on screen and one more on each side",
        arguments: [
            // Pages 0 and 1 on screen (1 partly), plus Page 2 below.
            (offset: 0, expected: 0..<3),
            // Page 0 partly, 1, and 2 partly on screen, plus Page 3 below.
            (offset: 250, expected: 0..<4),
            // Page 0 has just left the top: Pages 1 and 2 on screen, Pages 0 and 3 kept.
            (offset: 300, expected: 0..<4),
            // At the end: Pages 4 and 5 on screen, plus Page 3 above; nothing past the last.
            (offset: 1300, expected: 3..<6),
        ] as [(offset: CGFloat, expected: Range<Int>)])
    func pagesToDecode(offset: CGFloat, expected: Range<Int>) {
        #expect(sixPages.pagesToDecode(offset: offset, viewportHeight: 500) == expected)
    }

    @Test(
        "scrolled past either end, the nearest Page and its neighbour stay decoded",
        arguments: [
            // Pulled down past the top: Page 0 still partly on screen.
            (offset: -400, expected: 0..<2),
            // Nothing on screen above the first Page.
            (offset: -1000, expected: 0..<2),
            // Nothing on screen below the last Page.
            (offset: 5000, expected: 4..<6),
        ] as [(offset: CGFloat, expected: Range<Int>)])
    func pagesToDecodePastTheEnds(offset: CGFloat, expected: Range<Int>) {
        #expect(sixPages.pagesToDecode(offset: offset, viewportHeight: 500) == expected)
    }

    @Test("Pages shorter than the screen keep more Pages decoded than one tall Page does")
    func pagesToDecodeShortAndTall() {
        let short = StripGeometry(
            pixelSizes: Array(repeating: CGSize(width: 100, height: 100), count: 10), width: 100,
            displayScale: 1)
        // Pages 0 to 4 fill the screen, plus Page 5 below.
        #expect(short.pagesToDecode(offset: 0, viewportHeight: 500) == 0..<6)

        // Heights 300, 300, 3000, 300, 300: Page 2 runs from 600 to 3600.
        let tall = StripGeometry(
            pixelSizes: [
                CGSize(width: 100, height: 300), CGSize(width: 100, height: 300),
                CGSize(width: 100, height: 3000), CGSize(width: 100, height: 300),
                CGSize(width: 100, height: 300),
            ], width: 100, displayScale: 1)
        // Only Page 2 is on screen, plus one Page on each side.
        #expect(tall.pagesToDecode(offset: 1600, viewportHeight: 500) == 1..<4)
    }

    @Test("one Page is always kept decoded, and an empty strip keeps none")
    func pagesToDecodeOnePageAndEmpty() {
        let one = StripGeometry(
            pixelSizes: [CGSize(width: 100, height: 100)], width: 100, displayScale: 1)
        for offset: CGFloat in [-1000, 0, 50, 1000] {
            #expect(one.pagesToDecode(offset: offset, viewportHeight: 500) == 0..<1)
        }

        let empty = StripGeometry(pixelSizes: [], width: 100, displayScale: 1)
        #expect(empty.pagesToDecode(offset: 0, viewportHeight: 500).isEmpty)
    }

    @Test(
        "every Page's height and top falls on the screen's pixel grid, and the tops, the strip's height and the Page at the top agree",
        arguments: [2, 3] as [CGFloat])
    func pixelGrid(scale: CGFloat) {
        // 1000 x 1001 at 402 points wide is 402.402 points tall, on no pixel grid; a
        // non-image Page is a square, and 3 x 7 is 938 points tall.
        let exact: CGFloat = 402 * 1001 / 1000
        let geometry = StripGeometry(
            pixelSizes: Array(repeating: CGSize(width: 1000, height: 1001), count: 12) + [
                nil, CGSize(width: 3, height: 7),
            ], width: 402, displayScale: scale)

        for (top, height) in zip(geometry.tops, geometry.heights) {
            #expect((top * scale).rounded() == top * scale)
            #expect((height * scale).rounded() == height * scale)
        }
        #expect(abs(geometry.heights[0] - exact) <= 0.5 / scale)
        #expect(geometry.heights[12] == 402)
        // Tops are the heights added up, to the pixel, and so is the strip's height.
        func pixels(_ points: CGFloat) -> CGFloat { (points * scale).rounded() }
        for page in geometry.tops.indices.dropLast() {
            #expect(
                pixels(geometry.tops[page + 1] - geometry.tops[page])
                    == pixels(geometry.heights[page]))
        }
        #expect(pixels(geometry.contentHeight) == pixels(geometry.tops[13] + geometry.heights[13]))
        // A jump that lands exactly on a top reads that Page; one pixel above reads the one
        // before.
        for page in 1...11 {
            let top = geometry.tops[page]
            #expect(geometry.pageAtTop(offset: top, viewportHeight: 874) == page)
            #expect(geometry.pageAtTop(offset: top - 1 / scale, viewportHeight: 874) == page - 1)
        }
    }

    @Test(
        "after a zoom the reader stays at the same place inside the Page under the top of the screen"
    )
    func keepingPlace() {
        let zoomed = StripGeometry(
            pixelSizes: Array(repeating: CGSize(width: 100, height: 300), count: 6), width: 200,
            displayScale: 1)

        // Zoom in: halfway down Page 1 (300 to 600) stays halfway down it (600 to 1200).
        #expect(zoomed.offset(keepingPlaceOf: 450, in: sixPages) == 900)
        // Zoom out: the same place back again.
        #expect(sixPages.offset(keepingPlaceOf: 900, in: zoomed) == 450)
        // The first Page.
        #expect(zoomed.offset(keepingPlaceOf: 150, in: sixPages) == 300)
        // The last Page (1500 to 1800, then 3000 to 3600).
        #expect(zoomed.offset(keepingPlaceOf: 1650, in: sixPages) == 3300)
        // Pulled past either end, the place is the nearest end of the strip.
        #expect(zoomed.offset(keepingPlaceOf: -40, in: sixPages) == 0)
        #expect(zoomed.offset(keepingPlaceOf: 5000, in: sixPages) == zoomed.contentHeight)
    }

    @Test("a one-Page strip keeps the same place inside its Page, and an empty strip stays at 0")
    func keepingPlaceOnePageAndEmpty() {
        let one = StripGeometry(
            pixelSizes: [CGSize(width: 100, height: 100)], width: 100, displayScale: 1)
        let wider = StripGeometry(
            pixelSizes: [CGSize(width: 100, height: 100)], width: 250, displayScale: 1)
        #expect(wider.offset(keepingPlaceOf: 50, in: one) == 125)

        let empty = StripGeometry(pixelSizes: [], width: 100, displayScale: 1)
        #expect(empty.offset(keepingPlaceOf: 50, in: empty) == 0)
    }
}
