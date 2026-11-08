import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum CoverImageError: Error, Equatable {
    case undecodable
}

/// Renders the small Cover image the Library grid displays for a Book.
public enum CoverImage {
    public static let maxPixelSize = 600
    public static let fileName = "cover.jpg"

    private static let jpegQuality = 0.85

    /// Renders `page` downsampled to at most `maxPixelSize` on its longer side as JPEG at `destination`.
    /// Throws `CoverImageError.undecodable` when ImageIO cannot read the Page.
    public static func render(page: URL, to destination: URL) throws(CoverImageError) {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard
            let source = CGImageSourceCreateWithURL(page as CFURL, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
            let output = CGImageDestinationCreateWithURL(
                destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw .undecodable }

        CGImageDestinationAddImage(
            output, image,
            [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(output) else { throw .undecodable }
    }
}
