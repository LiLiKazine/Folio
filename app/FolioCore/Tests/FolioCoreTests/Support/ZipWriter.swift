import Compression
import Foundation

/// Builds small zip files for tests: stored or deflate entries, optionally with data
/// descriptors, a zip64 end record, or the encryption flag set.
struct ZipWriter {
    enum Method { case stored, deflate }

    struct EncodeFailed: Error {}

    var useDataDescriptor: Bool = false
    var zip64: Bool = false
    var encryptedFlag: Bool = false

    private var entries: [(name: String, data: Data, method: Method)] = []

    mutating func add(_ name: String, data: Data, method: Method) {
        entries.append((name, data, method))
    }

    func write(to url: URL) throws {
        var archive = Data()
        var centralDirectory = Data()

        for entry in entries {
            let name = Data(entry.name.utf8)
            let payload = entry.method == .deflate ? try Self.deflate(entry.data) : entry.data
            let crc = Self.crc32(entry.data)
            var flags: UInt16 = 1 << 11
            if useDataDescriptor { flags |= 1 << 3 }
            if encryptedFlag { flags |= 1 << 0 }
            let method: UInt16 = entry.method == .deflate ? 8 : 0
            let offset = UInt32(archive.count)

            archive.append(le32: 0x0403_4b50)
            archive.append(le16: 20)
            archive.append(le16: flags)
            archive.append(le16: method)
            archive.append(le32: 0)  // modification time and date
            archive.append(le32: useDataDescriptor ? 0 : crc)
            archive.append(le32: useDataDescriptor ? 0 : UInt32(payload.count))
            archive.append(le32: useDataDescriptor ? 0 : UInt32(entry.data.count))
            archive.append(le16: UInt16(name.count))
            archive.append(le16: 0)
            archive.append(name)
            archive.append(payload)
            if useDataDescriptor {
                archive.append(le32: 0x0807_4b50)
                archive.append(le32: crc)
                archive.append(le32: UInt32(payload.count))
                archive.append(le32: UInt32(entry.data.count))
            }

            centralDirectory.append(le32: 0x0201_4b50)
            centralDirectory.append(le16: 20)
            centralDirectory.append(le16: 20)
            centralDirectory.append(le16: flags)
            centralDirectory.append(le16: method)
            centralDirectory.append(le32: 0)
            centralDirectory.append(le32: crc)
            centralDirectory.append(le32: UInt32(payload.count))
            centralDirectory.append(le32: UInt32(entry.data.count))
            centralDirectory.append(le16: UInt16(name.count))
            centralDirectory.append(le16: 0)  // extra length
            centralDirectory.append(le16: 0)  // comment length
            centralDirectory.append(le16: 0)  // disk number
            centralDirectory.append(le16: 0)  // internal attributes
            centralDirectory.append(le32: 0)  // external attributes
            centralDirectory.append(le32: offset)
            centralDirectory.append(name)
        }

        let centralDirectoryOffset = archive.count
        archive.append(centralDirectory)

        if zip64 {
            let zip64EndOffset = archive.count
            archive.append(le32: 0x0606_4b50)
            archive.append(le64: 44)
            archive.append(le16: 45)
            archive.append(le16: 45)
            archive.append(le32: 0)
            archive.append(le32: 0)
            archive.append(le64: UInt64(entries.count))
            archive.append(le64: UInt64(entries.count))
            archive.append(le64: UInt64(centralDirectory.count))
            archive.append(le64: UInt64(centralDirectoryOffset))
            archive.append(le32: 0x0706_4b50)
            archive.append(le32: 0)
            archive.append(le64: UInt64(zip64EndOffset))
            archive.append(le32: 1)
        }

        archive.append(le32: 0x0605_4b50)
        archive.append(le16: 0)
        archive.append(le16: 0)
        archive.append(le16: zip64 ? 0xFFFF : UInt16(entries.count))
        archive.append(le16: zip64 ? 0xFFFF : UInt16(entries.count))
        archive.append(le32: zip64 ? 0xFFFF_FFFF : UInt32(centralDirectory.count))
        archive.append(le32: zip64 ? 0xFFFF_FFFF : UInt32(centralDirectoryOffset))
        archive.append(le16: 0)

        try archive.write(to: url)
    }

    /// Raw deflate (no zlib header), which is what zip method 8 stores.
    private static func deflate(_ data: Data) throws -> Data {
        let capacity = data.count + 1024
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_encode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { throw EncodeFailed() }
        return output.prefix(written)
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return ~crc
    }
}

extension Data {
    fileprivate mutating func append(le16 value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    fileprivate mutating func append(le32 value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    fileprivate mutating func append(le64 value: UInt64) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
