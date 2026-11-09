import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

/// Writes small PNG Pages for the tests that decode them.
enum PNGFixture {
    /// A fresh temporary directory, removed by the caller.
    static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SlicedPageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Red on the top half, blue on the bottom half, so a slice cut from the wrong rows
    /// would not look the same.
    static func write(to url: URL, width: Int, height: Int) throws {
        let picture = try draw(width: width, height: height) { context in
            context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        }
        try save(picture, to: url)
    }

    /// A picture `width` x `height` pixels in device RGB, drawn by `fill`.
    static func draw(width: Int, height: Int, _ fill: (CGContext) -> Void) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        fill(context)
        return try #require(context.makeImage())
    }

    /// Writes `picture` to `url` as a PNG.
    static func save(_ picture: CGImage, to url: URL) throws {
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, picture, nil)
        try #require(CGImageDestinationFinalize(destination))
    }
}
