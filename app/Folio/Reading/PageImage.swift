import CoreGraphics
import Foundation
import ImageIO

/// Decodes a Page for the screen.
enum PageImage {
    /// The Page at `url` downsampled so its longer side is at most `maxPixelSize`,
    /// with its orientation applied, or nil when the file is missing or ImageIO cannot
    /// read it. A Page that cannot be shown is expected input (the reading screen shows
    /// a placeholder), so it is logged as information, not as an error.
    static func decode(url: URL, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            AppLog.reading.info(
                "A Page could not be decoded: \(url.lastPathComponent, privacy: .private)")
            return nil
        }
        return image
    }

    /// The size in pixels of the Page at `url` as it is shown, with its orientation
    /// applied (a Page turned a quarter turn has its width and height swapped), read
    /// without decoding the image; nil when the file is missing or is not an image.
    static func pixelSize(url: URL) -> CGSize? {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? UInt32)
            .flatMap(CGImagePropertyOrientation.init(rawValue:))
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: height, height: width)
        default:
            return CGSize(width: width, height: height)
        }
    }
}
