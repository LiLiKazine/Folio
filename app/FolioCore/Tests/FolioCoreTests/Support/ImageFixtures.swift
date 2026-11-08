import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageFixtures {
    struct WriteFailure: Error {}

    /// Writes a solid-colour PNG of exactly `width` x `height` pixels at `url`.
    static func png(width: Int, height: Int, at url: URL) throws {
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw WriteFailure() }
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw WriteFailure() }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw WriteFailure() }
    }

    /// The pixel size ImageIO reports for the image at `url`.
    static func pixelSize(of url: URL) throws -> (width: Int, height: Int) {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw WriteFailure() }
        return (width, height)
    }
}
