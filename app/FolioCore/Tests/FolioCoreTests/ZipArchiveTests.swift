import Foundation
import Testing

@testable import FolioCore

@Suite("Zip archive")
struct ZipArchiveTests {
    private static let patterned = Data(
        (0..<65_536).map { UInt8(truncatingIfNeeded: ($0 * 7) ^ ($0 >> 9)) })

    /// Relative paths of every regular file under `directory`, sorted.
    private func files(under directory: URL) -> [String] {
        let base = directory.resolvingSymlinksInPath().path + "/"
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        var paths: [String] = []
        for case let url as URL in enumerator where !url.hasDirectoryPath {
            paths.append(String(url.resolvingSymlinksInPath().path.dropFirst(base.count)))
        }
        return paths.sorted()
    }

    private func write(_ writer: ZipWriter, in dir: TemporaryDirectory) throws -> URL {
        let url = dir.url.appending(path: "source.zip")
        try writer.write(to: url)
        return url
    }

    @Test("extracts stored entries")
    func stored() throws {
        let dir = try TemporaryDirectory()
        defer { dir.remove() }
        let first = Data("first page".utf8)
        let second = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF])
        var writer = ZipWriter()
        writer.add("a/1.jpg", data: first, method: .stored)
        writer.add("2.png", data: second, method: .stored)
        let out = dir.url.appending(path: "out")

        let archive = try ZipArchive(url: try write(writer, in: dir))
        var extracted: [String] = []
        try archive.extract(to: out) { extracted.append($0.name) }

        #expect(archive.entries.map(\.name) == ["a/1.jpg", "2.png"])
        #expect(archive.entries.map(\.uncompressedSize) == [first.count, second.count])
        #expect(extracted == ["a/1.jpg", "2.png"])
        #expect(try Data(contentsOf: out.appending(path: "a/1.jpg")) == first)
        #expect(try Data(contentsOf: out.appending(path: "2.png")) == second)
    }

    @Test("extracts deflate entries")
    func deflate() throws {
        let dir = try TemporaryDirectory()
        defer { dir.remove() }
        var writer = ZipWriter()
        writer.add("page.jpg", data: Self.patterned, method: .deflate)
        let out = dir.url.appending(path: "out")

        try ZipArchive(url: try write(writer, in: dir)).extract(to: out)

        #expect(try Data(contentsOf: out.appending(path: "page.jpg")) == Self.patterned)
    }

    @Test("handles data descriptors (bit 3)")
    func dataDescriptor() throws {
        let dir = try TemporaryDirectory()
        defer { dir.remove() }
        var writer = ZipWriter()
        writer.useDataDescriptor = true
        writer.add("1.jpg", data: Self.patterned, method: .deflate)
        writer.add("2.jpg", data: Data("second".utf8), method: .stored)
        let out = dir.url.appending(path: "out")

        try ZipArchive(url: try write(writer, in: dir)).extract(to: out)

        #expect(try Data(contentsOf: out.appending(path: "1.jpg")) == Self.patterned)
        #expect(try Data(contentsOf: out.appending(path: "2.jpg")) == Data("second".utf8))
    }

    @Test("decodes UTF-8 names (bit 11)")
    func utf8Names() throws {
        let dir = try TemporaryDirectory()
        defer { dir.remove() }
        let bytes = Data("ページ".utf8)
        var writer = ZipWriter()
        writer.add("第01話/ページ1.jpg", data: bytes, method: .stored)
        let out = dir.url.appending(path: "out")

        let archive = try ZipArchive(url: try write(writer, in: dir))
        try archive.extract(to: out)

        #expect(archive.entries.map(\.name) == ["第01話/ページ1.jpg"])
        #expect(try Data(contentsOf: out.appending(path: "第01話/ページ1.jpg")) == bytes)
    }

    @Test("rejects zip64 as unsupported")
    func zip64() throws {
        let dir = try TemporaryDirectory()
        defer { dir.remove() }
        var writer = ZipWriter()
        writer.zip64 = true
        writer.add("1.jpg", data: Data("x".utf8), method: .stored)
        let url = try write(writer, in: dir)

        #expect(throws: ZipError.unsupported) { try ZipArchive(url: url) }
    }

    @Test("rejects entries larger than the per-entry cap as unsupported")
    func oversized() throws {
        let dir = try TemporaryDirectory()
        defer { dir.remove() }
        var writer = ZipWriter()
        writer.add(
            "1.jpg", data: Data("x".utf8), method: .stored,
            declaredUncompressedSize: 0xFFFF_FFFE)
        let url = try write(writer, in: dir)

        #expect(throws: ZipError.unsupported) { try ZipArchive(url: url) }
    }

    @Test("rejects encrypted entries as unsupported")
    func encrypted() throws {
        let dir = try TemporaryDirectory()
        defer { dir.remove() }
        var writer = ZipWriter()
        writer.encryptedFlag = true
        writer.add("1.jpg", data: Data("x".utf8), method: .stored)
        let url = try write(writer, in: dir)
        let out = dir.url.appending(path: "out")

        #expect(throws: ZipError.unsupported) { try ZipArchive(url: url).extract(to: out) }
        #expect(files(under: out).isEmpty)
    }

    @Test("not a zip is unreadable")
    func garbage() throws {
        let dir = try TemporaryDirectory()
        defer { dir.remove() }
        let url = try dir.file("x.zip", bytes: Data("hello".utf8))

        #expect(throws: ZipError.unreadable) { try ZipArchive(url: url) }
    }

    @Test("ignores entries that escape the destination")
    func zipSlip() throws {
        let dir = try TemporaryDirectory()
        defer { dir.remove() }
        var writer = ZipWriter()
        writer.add("../evil.jpg", data: Data("evil".utf8), method: .stored)
        writer.add("/abs.jpg", data: Data("abs".utf8), method: .stored)
        writer.add("ok.jpg", data: Data("ok".utf8), method: .stored)
        let out = dir.url.appending(path: "out")

        try ZipArchive(url: try write(writer, in: dir)).extract(to: out)

        #expect(files(under: out) == ["ok.jpg"])
        #expect(try Data(contentsOf: out.appending(path: "ok.jpg")) == Data("ok".utf8))
        #expect(!FileManager.default.fileExists(atPath: dir.url.appending(path: "evil.jpg").path))
    }

    @Test("ignores directory entries and __MACOSX")
    func dirs() throws {
        let dir = try TemporaryDirectory()
        defer { dir.remove() }
        var writer = ZipWriter()
        writer.add("a/", data: Data(), method: .stored)
        writer.add("__MACOSX/._x.jpg", data: Data("fork".utf8), method: .stored)
        writer.add("a/x.jpg", data: Data("x".utf8), method: .stored)
        let out = dir.url.appending(path: "out")

        let archive = try ZipArchive(url: try write(writer, in: dir))
        var extracted: [String] = []
        try archive.extract(to: out) { extracted.append($0.name) }

        #expect(archive.entries.map(\.isDirectory) == [true, false, false])
        #expect(extracted == ["a/x.jpg"])
        #expect(files(under: out) == ["a/x.jpg"])
    }
}
