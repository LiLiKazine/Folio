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
}
