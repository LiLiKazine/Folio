import Compression
import Foundation

/// Raw deflate decoding (zip method 8) on the Compression framework.
enum Inflate {
    /// Decodes `data` as raw deflate. Throws `.unreadable` unless the stream decodes
    /// to exactly `expectedSize` bytes.
    static func decode(_ data: Data, expectedSize: Int) throws(ZipError) -> Data {
        guard expectedSize > 0 else { return Data() }
        guard !data.isEmpty else { throw .unreadable }
        // One spare byte: filling it means the stream is longer than declared.
        let capacity = expectedSize + 1
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expectedSize else { throw .unreadable }
        return output.prefix(written)
    }
}
