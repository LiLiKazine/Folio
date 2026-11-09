import CoreGraphics
import Testing

@testable import Folio

@Suite("StripGeometry")
struct StripGeometryTests {
    @Test("heights fit each Page to the width; a Page with no pixel size is a square")
    func heightsAndTops() {
        let geometry = StripGeometry(
            pixelSizes: [CGSize(width: 800, height: 1200), nil, CGSize(width: 800, height: 400)],
            width: 400)

        #expect(geometry.heights == [600, 400, 200])
        #expect(geometry.tops == [0, 600, 1000])
        #expect(geometry.contentHeight == 1200)
    }

    @Test("a Page whose pixel size has no area is a square, not a division by zero")
    func degeneratePixelSize() {
        let geometry = StripGeometry(
            pixelSizes: [CGSize(width: 0, height: 10), CGSize(width: 10, height: 0)], width: 300)

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
            ], width: 400)
        #expect(geometry.heights == [600, 400, 200])

        #expect(geometry.pageAtTop(offset: offset, viewportHeight: 500) == expected)
    }

    @Test("a strip shorter than the screen stays on its first Page until it is scrolled")
    func shortPages() {
        let geometry = StripGeometry(
            pixelSizes: Array(repeating: CGSize(width: 100, height: 100), count: 4), width: 100)

        #expect(geometry.pageAtTop(offset: 0, viewportHeight: 500) == 0)
        #expect(geometry.pageAtTop(offset: 1, viewportHeight: 500) == 3)
    }

    @Test("one Page is always Page 0, and an empty strip is Page 0")
    func onePageAndEmpty() {
        let one = StripGeometry(pixelSizes: [CGSize(width: 100, height: 100)], width: 100)
        for offset: CGFloat in [-10, 0, 50] {
            #expect(one.pageAtTop(offset: offset, viewportHeight: 500) == 0)
        }

        let empty = StripGeometry(pixelSizes: [], width: 100)
        #expect(empty.heights.isEmpty)
        #expect(empty.contentHeight == 0)
        #expect(empty.pageAtTop(offset: 100, viewportHeight: 500) == 0)
    }

    /// Six Pages 300 points tall: tops 0, 300, 600, 900, 1200, 1500; the strip is 1800.
    private let sixPages = StripGeometry(
        pixelSizes: Array(repeating: CGSize(width: 100, height: 300), count: 6), width: 100)

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
            pixelSizes: Array(repeating: CGSize(width: 100, height: 100), count: 10), width: 100)
        // Pages 0 to 4 fill the screen, plus Page 5 below.
        #expect(short.pagesToDecode(offset: 0, viewportHeight: 500) == 0..<6)

        // Heights 300, 300, 3000, 300, 300: Page 2 runs from 600 to 3600.
        let tall = StripGeometry(
            pixelSizes: [
                CGSize(width: 100, height: 300), CGSize(width: 100, height: 300),
                CGSize(width: 100, height: 3000), CGSize(width: 100, height: 300),
                CGSize(width: 100, height: 300),
            ], width: 100)
        // Only Page 2 is on screen, plus one Page on each side.
        #expect(tall.pagesToDecode(offset: 1600, viewportHeight: 500) == 1..<4)
    }

    @Test("one Page is always kept decoded, and an empty strip keeps none")
    func pagesToDecodeOnePageAndEmpty() {
        let one = StripGeometry(pixelSizes: [CGSize(width: 100, height: 100)], width: 100)
        for offset: CGFloat in [-1000, 0, 50, 1000] {
            #expect(one.pagesToDecode(offset: offset, viewportHeight: 500) == 0..<1)
        }

        let empty = StripGeometry(pixelSizes: [], width: 100)
        #expect(empty.pagesToDecode(offset: 0, viewportHeight: 500).isEmpty)
    }
}
