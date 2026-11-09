import CoreGraphics
import Foundation

/// A tall Page decoded for the Vertical strip: sharp at the screen's width, cut into
/// slices so no single image is too tall for the screen to take, and sized to stay within
/// a byte budget.
enum SlicedPage {
    /// The most rows in one slice, in pixels; under every GPU texture limit the design
    /// names (8,192 and 16,384).
    static let sliceMaxHeight = 2048

    /// The most bytes one decoded Page may take: 96 MB on iPhone and iPad, 256 MB on Mac.
    static func perPageBudget() -> Int {
        #if os(macOS)
            256 * 1024 * 1024
        #else
            96 * 1024 * 1024
        #endif
    }

    /// The width in pixels to decode a Page at: the smaller of its own width and the
    /// screen's, lowered until width x height x 4 bytes is within `budget` with the Page's
    /// proportions kept; at least 1.
    static func decodeWidth(pageSize: CGSize, screenWidthPixels: Int, budget: Int) -> Int {
        let ceiling = max(1, min(Int(pageSize.width.rounded(.down)), screenWidthPixels))
        guard pageSize.width > 0, pageSize.height > 0 else { return ceiling }
        func bytes(at width: Int) -> Int {
            width * scaledHeight(of: pageSize, atWidth: width) * 4
        }
        // The bytes grow with the width, so the widest width that fits is found by halving.
        var low = 1
        var high = ceiling
        while low < high {
            let middle = (low + high + 1) / 2
            if bytes(at: middle) <= budget { low = middle } else { high = middle - 1 }
        }
        return low
    }

    /// Decodes the Page at `url` at `width` pixels wide, then cuts it into slices of at most
    /// `sliceMaxHeight` rows, top to bottom. The decoded Page is only held while the slices
    /// are cut; each slice is its own bitmap, so none keeps the whole Page in memory.
    /// Nil when the Page cannot be decoded.
    static func decode(url: URL, width: Int) -> [CGImage]? {
        guard let pageSize = PageImage.pixelSize(url: url), pageSize.width > 0, width > 0 else {
            AppLog.reading.info(
                "A Page could not be decoded: \(url.lastPathComponent, privacy: .private)")
            return nil
        }
        // ImageIO limits the longer side of the result, so the limit is the height at
        // `width` for a tall Page and `width` itself for a wide one.
        let longerSide =
            pageSize.height >= pageSize.width
            ? scaledHeight(of: pageSize, atWidth: width) : width
        guard let image = PageImage.decode(url: url, maxPixelSize: longerSide) else { return nil }
        return slices(of: image)
    }

    /// The bytes the slices hold: each slice's rows times its bytes per row.
    static func bytes(of slices: [CGImage]) -> Int {
        slices.reduce(0) { $0 + $1.bytesPerRow * $1.height }
    }

    /// The Page's height in pixels when it is `width` pixels wide, rounded up.
    private static func scaledHeight(of pageSize: CGSize, atWidth width: Int) -> Int {
        Int((Double(width) * pageSize.height / pageSize.width).rounded(.up))
    }

    /// Draws each band of rows of `image` into a bitmap of its own. Cropping would be
    /// cheaper, but Apple documents that "the resulting image retains a reference to the
    /// original image", which would keep every slice's whole Page alive.
    private static func slices(of image: CGImage) -> [CGImage]? {
        var slices: [CGImage] = []
        var top = 0
        while top < image.height {
            let height = min(sliceMaxHeight, image.height - top)
            guard let context = makeContext(width: image.width, height: height, like: image)
            else { return nil }
            context.interpolationQuality = .none
            // Core Graphics counts up from the bottom: this places the image's row `top`
            // on the context's top row.
            context.draw(
                image,
                in: CGRect(
                    x: 0, y: height - image.height + top, width: image.width, height: image.height))
            guard let slice = context.makeImage() else { return nil }
            slices.append(slice)
            top += height
        }
        return slices
    }

    /// An 8-bit RGBA bitmap in the image's own colour space when that is an RGB one the
    /// bitmap can use, otherwise in device RGB.
    private static func makeContext(width: Int, height: Int, like image: CGImage) -> CGContext? {
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        var spaces = [CGColorSpaceCreateDeviceRGB()]
        if let own = image.colorSpace, own.model == .rgb { spaces.insert(own, at: 0) }
        for space in spaces {
            if let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: bitmapInfo)
            {
                return context
            }
        }
        return nil
    }
}
