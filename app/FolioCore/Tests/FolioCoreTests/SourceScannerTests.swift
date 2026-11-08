import Foundation
import Testing

@testable import FolioCore

@Suite("Source scanning")
struct SourceScannerTests {
    private func relativePaths(_ dir: TemporaryDirectory) throws -> [String] {
        let base = dir.url.resolvingSymlinksInPath().path + "/"
        return try SourceScanner.pageFiles(in: dir.url).map {
            String($0.resolvingSymlinksInPath().path.dropFirst(base.count))
        }
    }

    @Test("orders naturally so page2 precedes page10")
    func naturalOrder() throws {
        let dir = try TemporaryDirectory()
        defer { dir.remove() }
        for name in ["page10.jpg", "page2.jpg", "page1.jpg"] { try dir.file(name) }
        #expect(
            try SourceScanner.pageFiles(in: dir.url).map(\.lastPathComponent)
                == ["page1.jpg", "page2.jpg", "page10.jpg"])
    }

    @Test("flattens subfolders in relative-path order")
    func flattens() throws {
        let dir = try TemporaryDirectory()
        defer { dir.remove() }
        for name in ["b/01.png", "a/02.png", "a/01.png"] { try dir.file(name) }
        #expect(try relativePaths(dir) == ["a/01.png", "a/02.png", "b/01.png"])
    }

    @Test("keeps only Page extensions, case-insensitively")
    func extensions() throws {
        let dir = try TemporaryDirectory()
        defer { dir.remove() }
        for name in ["x.JPG", "y.Png", "z.txt", "w.heic", "v.webp", "u.gif", "t.jpeg", "s.bmp"] {
            try dir.file(name)
        }
        let names = try SourceScanner.pageFiles(in: dir.url).map(\.lastPathComponent)
        #expect(names.count == 6)
        #expect(!names.contains("z.txt"))
        #expect(!names.contains("s.bmp"))
    }

    @Test("skips hidden files and __MACOSX")
    func skipsJunk() throws {
        let dir = try TemporaryDirectory()
        defer { dir.remove() }
        for name in [".DS_Store", "._01.jpg", "__MACOSX/01.jpg", "01.jpg"] { try dir.file(name) }
        #expect(try relativePaths(dir) == ["01.jpg"])
    }

    @Test("empty folder yields no Pages")
    func empty() throws {
        let dir = try TemporaryDirectory()
        defer { dir.remove() }
        #expect(try SourceScanner.pageFiles(in: dir.url).isEmpty)
    }

    @Test("title is the item's own name without extension")
    func title() {
        #expect(
            SourceScanner.title(forSource: URL(fileURLWithPath: "/x/One Piece/Chapter 01"))
                == "Chapter 01")
        #expect(SourceScanner.title(forSource: URL(fileURLWithPath: "/x/op-vol3.zip")) == "op-vol3")
        #expect(SourceScanner.title(forSource: URL(fileURLWithPath: "/x/Vol.3.zip")) == "Vol.3")
        #expect(SourceScanner.title(forSource: URL(fileURLWithPath: "/x/Vol.3")) == "Vol.3")
        #expect(SourceScanner.title(forSource: URL(fileURLWithPath: "/x/A.ZIP")) == "A")
    }

    @Test("a directory or symbolic link with a Page extension is not a Page")
    func onlyRegularFiles() throws {
        let dir = try TemporaryDirectory()
        defer { dir.remove() }
        let target = try dir.file("a.png")
        try FileManager.default.createDirectory(
            at: dir.url.appending(path: "x.jpg"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: dir.url.appending(path: "y.png"), withDestinationURL: target)
        #expect(try relativePaths(dir) == ["a.png"])
    }

    @Test("a Source inside a folder named __MACOSX still yields its Pages")
    func macosxAboveSource() throws {
        let dir = try TemporaryDirectory()
        defer { dir.remove() }
        try dir.file("__MACOSX/Source/01.png")
        try dir.file("__MACOSX/Source/__MACOSX/._01.png")
        try dir.file("__MACOSX/Source/__MACOSX/02.png")
        let source = dir.url.appending(path: "__MACOSX/Source")
        #expect(
            try SourceScanner.pageFiles(in: source).map(\.lastPathComponent) == ["01.png"])
    }
}
