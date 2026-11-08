import Foundation

public enum ZipError: Error, Equatable {
    /// Not a zip, or a damaged one.
    case unreadable
    /// A valid zip using a feature Folio does not read: zip64, encryption, or a
    /// compression method other than stored or deflate.
    case unsupported
}

/// Reads a zip Source: stored and deflate entries, no zip64, no encryption.
/// Only the central directory is held in memory; entry data is read one entry at a time.
public struct ZipArchive: Sendable {
    public struct Entry: Sendable, Equatable {
        public let name: String
        public let isDirectory: Bool
        public let uncompressedSize: Int
    }

    private struct Record: Sendable {
        let entry: Entry
        let method: UInt16
        let compressedSize: Int
        let localHeaderOffset: UInt64
    }

    private static let endSignature: UInt32 = 0x0605_4b50
    private static let zip64LocatorSignature: UInt32 = 0x0706_4b50
    private static let centralSignature: UInt32 = 0x0201_4b50
    private static let localSignature: UInt32 = 0x0403_4b50
    private static let endRecordSize = 22
    private static let zip64LocatorSize = 20
    private static let maxCommentSize = 0xFFFF

    private let url: URL
    private let records: [Record]

    public var entries: [Entry] { records.map(\.entry) }

    /// Reads the central directory only.
    public init(url: URL) throws(ZipError) {
        self.url = url
        let handle = try Self.io { try FileHandle(forReadingFrom: url) }
        defer { try? handle.close() }

        let fileSize = try Self.io { try handle.seekToEnd() }
        let tailSize = min(fileSize, UInt64(Self.endRecordSize + Self.maxCommentSize))
        let tailStart = fileSize - tailSize
        let tail = try Self.read(handle, at: tailStart, count: Int(tailSize))
        guard let endIndex = Self.lastIndex(of: Self.endSignature, in: tail) else {
            throw .unreadable
        }

        var end = ByteReader(tail, at: endIndex + 4)
        let diskNumber = try end.u16()
        let centralDisk = try end.u16()
        let entriesOnDisk = try end.u16()
        let entryCount = try end.u16()
        let centralSize = try end.u32()
        let centralOffset = try end.u32()
        if entriesOnDisk == 0xFFFF || entryCount == 0xFFFF || centralSize == 0xFFFF_FFFF
            || centralOffset == 0xFFFF_FFFF
        {
            throw .unsupported
        }
        let endOffset = tailStart + UInt64(endIndex)
        if endOffset >= UInt64(Self.zip64LocatorSize) {
            let locator = try Self.read(
                handle, at: endOffset - UInt64(Self.zip64LocatorSize), count: 4)
            var locatorReader = ByteReader(locator, at: 0)
            if try locatorReader.u32() == Self.zip64LocatorSignature {
                throw .unsupported
            }
        }
        guard diskNumber == 0, centralDisk == 0, entriesOnDisk == entryCount,
            UInt64(centralOffset) + UInt64(centralSize) <= endOffset
        else { throw .unreadable }

        let central = try Self.read(handle, at: UInt64(centralOffset), count: Int(centralSize))
        var reader = ByteReader(central, at: 0)
        var records: [Record] = []
        records.reserveCapacity(Int(entryCount))
        for _ in 0..<entryCount {
            records.append(try Self.readCentralHeader(&reader))
        }
        self.records = records
    }

    /// Extracts every file entry under `directory`, preserving relative paths.
    /// Ignores directory entries, anything under `__MACOSX`, and entries whose
    /// normalised path escapes `directory`. Calls `onEntry` after each file.
    public func extract(to directory: URL, onEntry: (Entry) -> Void = { _ in }) throws(ZipError) {
        let root = directory.standardizedFileURL
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        try Self.io {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        let handle = try Self.io { try FileHandle(forReadingFrom: url) }
        defer { try? handle.close() }

        for record in records {
            let name = record.entry.name
            guard !record.entry.isDirectory, !name.hasPrefix("/"),
                !name.split(separator: "/").contains("__MACOSX")
            else { continue }
            let destination = root.appending(path: name).standardizedFileURL
            guard destination.path.hasPrefix(rootPrefix) else { continue }

            let data = try contents(of: record, from: handle)
            try Self.io {
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: destination)
            }
            onEntry(record.entry)
        }
    }

    private func contents(of record: Record, from handle: FileHandle) throws(ZipError) -> Data {
        let header = try Self.read(handle, at: record.localHeaderOffset, count: 30)
        var reader = ByteReader(header, at: 0)
        guard try reader.u32() == Self.localSignature else { throw .unreadable }
        reader.skip(22)
        let nameLength = try reader.u16()
        let extraLength = try reader.u16()
        let dataStart = record.localHeaderOffset + 30 + UInt64(nameLength) + UInt64(extraLength)
        let compressed = try Self.read(handle, at: dataStart, count: record.compressedSize)

        switch record.method {
        case 0:
            guard compressed.count == record.entry.uncompressedSize else { throw .unreadable }
            return compressed
        default:
            return try Inflate.decode(compressed, expectedSize: record.entry.uncompressedSize)
        }
    }

    private static func readCentralHeader(_ reader: inout ByteReader) throws(ZipError) -> Record {
        guard try reader.u32() == centralSignature else { throw .unreadable }
        reader.skip(4)  // version made by, version needed
        let flags = try reader.u16()
        let method = try reader.u16()
        reader.skip(8)  // modification time and date, CRC-32
        let compressedSize = try reader.u32()
        let uncompressedSize = try reader.u32()
        let nameLength = try reader.u16()
        let extraLength = try reader.u16()
        let commentLength = try reader.u16()
        reader.skip(8)  // disk number, internal and external attributes
        let localHeaderOffset = try reader.u32()
        let nameBytes = try reader.bytes(Int(nameLength))
        reader.skip(Int(extraLength) + Int(commentLength))

        if flags & 1 != 0 { throw .unsupported }
        guard method == 0 || method == 8 else { throw .unsupported }
        if compressedSize == 0xFFFF_FFFF || uncompressedSize == 0xFFFF_FFFF
            || localHeaderOffset == 0xFFFF_FFFF
        {
            throw .unsupported
        }

        let name = try decodeName(nameBytes, isUTF8: flags & (1 << 11) != 0)
        return Record(
            entry: Entry(
                name: name, isDirectory: name.hasSuffix("/"),
                uncompressedSize: Int(uncompressedSize)),
            method: method,
            compressedSize: Int(compressedSize),
            localHeaderOffset: UInt64(localHeaderOffset))
    }

    /// Bit 11 marks UTF-8. Without it the spec says CP437, but many tools write
    /// UTF-8 anyway, so valid UTF-8 wins and CP437 is the fallback.
    private static func decodeName(_ bytes: Data, isUTF8: Bool) throws(ZipError) -> String {
        if let name = String(data: bytes, encoding: .utf8) { return name }
        guard !isUTF8 else { throw .unreadable }
        let cp437 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.dosLatinUS.rawValue)))
        guard let name = String(data: bytes, encoding: cp437) else { throw .unreadable }
        return name
    }

    private static func lastIndex(of signature: UInt32, in data: Data) -> Int? {
        let bytes = [UInt8](data)
        guard bytes.count >= endRecordSize else { return nil }
        let wanted: [UInt8] = [
            UInt8(signature & 0xFF), UInt8((signature >> 8) & 0xFF),
            UInt8((signature >> 16) & 0xFF), UInt8(signature >> 24),
        ]
        for index in stride(from: bytes.count - endRecordSize, through: 0, by: -1)
        where bytes[index..<index + 4].elementsEqual(wanted) {
            return index
        }
        return nil
    }

    private static func read(
        _ handle: FileHandle, at offset: UInt64, count: Int
    ) throws(ZipError)
        -> Data
    {
        guard count > 0 else { return Data() }
        let data = try io { () throws -> Data? in
            try handle.seek(toOffset: offset)
            return try handle.read(upToCount: count)
        }
        guard let data, data.count == count else { throw .unreadable }
        return data
    }

    /// Runs a Foundation call, mapping any error it throws to `.unreadable`.
    private static func io<T>(_ body: () throws -> T) throws(ZipError) -> T {
        do { return try body() } catch { throw .unreadable }
    }
}

/// Bounds-checked little-endian reads over a zero-based copy of some bytes.
private struct ByteReader {
    private let bytes: [UInt8]
    private var position: Int

    init(_ data: Data, at position: Int) {
        bytes = [UInt8](data)
        self.position = position
    }

    mutating func skip(_ count: Int) { position += count }

    mutating func u16() throws(ZipError) -> UInt16 {
        UInt16(try uint(2))
    }

    mutating func u32() throws(ZipError) -> UInt32 {
        UInt32(try uint(4))
    }

    private mutating func uint(_ count: Int) throws(ZipError) -> UInt64 {
        try take(count).reversed().reduce(0) { $0 << 8 | UInt64($1) }
    }

    mutating func bytes(_ count: Int) throws(ZipError) -> Data { Data(try take(count)) }

    private mutating func take(_ count: Int) throws(ZipError) -> ArraySlice<UInt8> {
        guard position >= 0, count >= 0, position + count <= bytes.count else { throw .unreadable }
        defer { position += count }
        return bytes[position..<position + count]
    }
}
