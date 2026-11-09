import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Folio

@Suite("PageImage")
struct PageImageTests {
    /// A fresh temporary directory, removed by the caller.
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "PageImageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writePNG(to url: URL, width: Int = 64, height: Int = 96) throws {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    @Test("decode downsamples a Page to the longer side at most maxPixelSize")
    func decodeDownsamples() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "0001.png")
        try writePNG(to: url, width: 64, height: 96)

        let image = try #require(PageImage.decode(url: url, maxPixelSize: 48))

        #expect(image.height == 48)
        #expect(image.width == 32)
    }

    @Test("decode returns nil for a file that is not an image, and for a missing file")
    func decodeUndecodable() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let notAnImage = directory.appending(path: "0001.png")
        try Data("not a Page".utf8).write(to: notAnImage)

        #expect(PageImage.decode(url: notAnImage, maxPixelSize: 48) == nil)
        #expect(
            PageImage.decode(url: directory.appending(path: "gone.png"), maxPixelSize: 48) == nil)
    }

    @Test(
        "pixelSize reads a Page's size without decoding it, and is nil for a file that is not an image"
    )
    func pixelSize() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let png = directory.appending(path: "0001.png")
        try writePNG(to: png, width: 64, height: 96)
        let notAnImage = directory.appending(path: "0002.png")
        try Data("not a Page".utf8).write(to: notAnImage)

        #expect(PageImage.pixelSize(url: png) == CGSize(width: 64, height: 96))
        #expect(PageImage.pixelSize(url: notAnImage) == nil)
        #expect(PageImage.pixelSize(url: directory.appending(path: "gone.png")) == nil)
    }

    @Test("pixelSize swaps width and height for an orientation that turns the Page a quarter turn")
    func pixelSizeAppliesOrientation() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let upright = directory.appending(path: "up.jpg")
        let turned = directory.appending(path: "turned.jpg")
        try writeJPEG(to: upright, width: 64, height: 96, orientation: .up)
        try writeJPEG(to: turned, width: 64, height: 96, orientation: .right)

        #expect(PageImage.pixelSize(url: upright) == CGSize(width: 64, height: 96))
        #expect(PageImage.pixelSize(url: turned) == CGSize(width: 96, height: 64))
    }

    private func writeJPEG(
        to url: URL, width: Int, height: Int, orientation: CGImagePropertyOrientation
    ) throws {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let destination = try #require(
            CGImageDestinationCreateWithURL(
                url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(
            destination, image, [kCGImagePropertyOrientation: orientation.rawValue] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
    }

    /// Writes `count` Pages and returns their URLs in order.
    private func makePages(count: Int, in directory: URL) throws -> [URL] {
        try (1...count).map { number in
            let url = directory.appending(path: String(format: "%04d.png", number))
            try writePNG(to: url)
            return url
        }
    }

    @Test("cache keeps the current Page and one each side")
    func cacheWindow() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PageImageCache(urls: try makePages(count: 5, in: directory), maxPixelSize: 48)

        #expect(await cache.image(at: 2) != nil)
        await cache.prefetch(around: 2)
        #expect(await cache.decodeCount == 3)  // Pages 2, 1, and 3 (0-based)

        await cache.prefetch(around: 4)  // keeps 3 and 4; drops 0, 1, and 2
        #expect(await cache.decodeCount == 3)  // Page 3 was already held; 5 does not exist
        #expect(await cache.image(at: 3) != nil)
        #expect(await cache.decodeCount == 3)
        #expect(await cache.image(at: 0) != nil)
        #expect(await cache.decodeCount == 4)  // Page 0 had to be decoded again
    }

    @Test("a Page that cannot be decoded is remembered as such, not retried")
    func brokenPageNotRetried() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let broken = directory.appending(path: "0001.png")
        try Data("not a Page".utf8).write(to: broken)
        let cache = PageImageCache(urls: [broken], maxPixelSize: 48)

        #expect(await cache.image(at: 0) == nil)
        #expect(await cache.image(at: 0) == nil)
        #expect(await cache.decodeCount == 1)
    }

    @Test("a decode asked for by a task that was cancelled does not run")
    func cancelledRequestDoesNotDecode() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PageImageCache(urls: try makePages(count: 3, in: directory), maxPixelSize: 48)

        // A Page that scrolled away cancels its task before the cache reaches the request.
        let request = Task {
            while !Task.isCancelled { await Task.yield() }
            return await cache.image(at: 1)
        }
        request.cancel()

        #expect(await request.value == nil)
        #expect(await cache.decodeCount == 0)
    }

    @Test("an index outside the Pages yields nil without decoding")
    func indexOutOfRange() async throws {
        let cache = PageImageCache(urls: [], maxPixelSize: 48)

        #expect(await cache.image(at: 0) == nil)
        await cache.prefetch(around: 0)
        #expect(await cache.decodeCount == 0)
    }
}
