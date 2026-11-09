import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Folio

/// Writes small two-colour PNG Pages for the tall-Page tests.
enum PNGFixture {
    static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SlicedPageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Red on the top half, blue on the bottom half, so a slice cut from the wrong rows
    /// would not look the same.
    static func write(to url: URL, width: Int, height: Int) throws {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        let image = try #require(context.makeImage())
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}

@Suite("SlicedPage")
struct SlicedPageTests {
    private let megabyte = 1024 * 1024

    @Test("a Page narrower than the screen is decoded at its own width")
    func narrowPageKeepsItsWidth() {
        let width = SlicedPage.decodeWidth(
            pageSize: CGSize(width: 800, height: 12000), screenWidthPixels: 1179,
            budget: 96 * megabyte)

        #expect(width == 800)
    }

    @Test("a Page wider than the screen is decoded at the screen's width when that fits the budget")
    func widePageIsCappedAtTheScreen() {
        let width = SlicedPage.decodeWidth(
            pageSize: CGSize(width: 3000, height: 40000), screenWidthPixels: 1179,
            budget: 96 * megabyte)

        // 1179 wide is 1179 x 15,720 pixels, about 74 MB: inside 96 MB.
        #expect(width == 1179)
    }

    @Test("a Page too tall for the budget is decoded narrower, to the widest width that fits")
    func tallPageIsLoweredToTheBudget() {
        let budget = 32 * megabyte
        let pageSize = CGSize(width: 3000, height: 40000)
        func bytes(at width: Int) -> Int {
            width * Int((Double(width) * pageSize.height / pageSize.width).rounded(.up)) * 4
        }

        let width = SlicedPage.decodeWidth(
            pageSize: pageSize, screenWidthPixels: 1179, budget: budget)

        #expect(width < 1179)
        #expect(bytes(at: width) <= budget)
        #expect(bytes(at: width + 1) > budget)
    }

    @Test("the width is at least 1, however small the budget, and never above the Page's own")
    func widthBounds() {
        #expect(
            SlicedPage.decodeWidth(
                pageSize: CGSize(width: 800, height: 12000), screenWidthPixels: 1179, budget: 1)
                == 1)
        #expect(
            SlicedPage.decodeWidth(
                pageSize: CGSize(width: 100, height: 100), screenWidthPixels: 1179,
                budget: 96 * megabyte) == 100)
    }

    @Test("decode cuts a tall Page into slices of at most 2,048 rows that add up to its height")
    func decodeSlices() throws {
        let directory = try PNGFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "0001.png")
        try PNGFixture.write(to: url, width: 64, height: 5000)

        let slices = try #require(SlicedPage.decode(url: url, width: 64))

        #expect(slices.map(\.height) == [2048, 2048, 904])
        #expect(slices.allSatisfy { $0.width == 64 })
        #expect(
            SlicedPage.bytes(of: slices) == slices.map { $0.bytesPerRow * $0.height }.reduce(0, +))
    }

    @Test("decode at a narrower width scales the whole Page, and its slices still add up")
    func decodeNarrower() throws {
        let directory = try PNGFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "0001.png")
        try PNGFixture.write(to: url, width: 64, height: 5000)

        let slices = try #require(SlicedPage.decode(url: url, width: 32))

        #expect(slices.allSatisfy { $0.width == 32 })
        #expect(slices.map(\.height).reduce(0, +) == 2500)
        #expect(slices.allSatisfy { $0.height <= SlicedPage.sliceMaxHeight })
    }

    @Test("slices keep the rows of the Page in order")
    func slicesKeepRowOrder() throws {
        let directory = try PNGFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "0001.png")
        try PNGFixture.write(to: url, width: 8, height: 4096 + 1000)

        let slices = try #require(SlicedPage.decode(url: url, width: 8))

        func firstPixel(of image: CGImage) throws -> [UInt8] {
            let data = try #require(image.dataProvider?.data)
            let bytes = try #require(CFDataGetBytePtr(data))
            return [bytes[0], bytes[1], bytes[2]]
        }
        #expect(try firstPixel(of: slices[0]) == [255, 0, 0])
        #expect(try firstPixel(of: slices[slices.count - 1]) == [0, 0, 255])
    }

    @Test("decode returns nil for a file that is not an image, and for a missing file")
    func decodeUndecodable() throws {
        let directory = try PNGFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let notAnImage = directory.appending(path: "0001.png")
        try Data("not a Page".utf8).write(to: notAnImage)

        #expect(SlicedPage.decode(url: notAnImage, width: 64) == nil)
        #expect(SlicedPage.decode(url: directory.appending(path: "gone.png"), width: 64) == nil)
    }
}
