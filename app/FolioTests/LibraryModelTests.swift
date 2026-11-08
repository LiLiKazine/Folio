import CoreGraphics
import FolioCore
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Folio

@Suite("LibraryModel")
@MainActor struct LibraryModelTests {
    /// A Library over in-memory repositories and a fresh temp Books directory, plus
    /// the root that holds both the Books directory and any Sources the test makes.
    private struct Fixture {
        let root: URL
        let booksDirectory: URL
        let model: LibraryModel
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "LibraryModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let booksDirectory = root.appending(path: "Books", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: booksDirectory, withIntermediateDirectories: true)
        let library = Library(
            books: InMemoryBookRepository(), imports: InMemoryImportRepository(),
            pipeline: ImportPipeline(booksDirectory: booksDirectory),
            sourceAccess: InMemorySourceAccess())
        return Fixture(
            root: root, booksDirectory: booksDirectory,
            model: LibraryModel(library: library, booksDirectory: booksDirectory))
    }

    /// A folder Source named `name` holding `pageCount` solid 64x96 PNG Pages.
    private func makeImageSource(named name: String, pageCount: Int, in root: URL) throws -> URL {
        let folder = root.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 1...pageCount {
            try writePNG(to: folder.appending(path: String(format: "%03d.png", index)))
        }
        return folder
    }

    private func writePNG(to url: URL) throws {
        let width = 64
        let height = 96
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    /// Polls every 50 ms until `condition` holds; records an issue after 5 s.
    private func waitUntil(
        _ description: String, sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record(
                    "Timed out waiting until \(description)", sourceLocation: sourceLocation)
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func books(in items: [LibraryItem]) -> [Book] {
        items.compactMap {
            if case .book(let book) = $0 { book } else { nil }
        }
    }

    private func startModel(_ model: LibraryModel) async throws -> Task<Void, Never> {
        let task = Task { await model.start() }
        try await waitUntil("the model is loaded") { model.isLoaded }
        return task
    }

    @Test("importing a folder ends with one Book item") func importFlow() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model
        let task = try await startModel(model)
        defer { task.cancel() }

        let source = try makeImageSource(named: "Volume One", pageCount: 3, in: fixture.root)
        await model.importSource(source)

        try await waitUntil("one Book is the only item") {
            model.items.count == 1 && books(in: model.items).count == 1
        }
        let book = try #require(books(in: model.items).first)
        #expect(book.title == "Volume One")
        #expect(book.pages.count == 3)
        #expect(
            model.coverURL(for: book)
                == fixture.booksDirectory.appending(path: book.folderName)
                .appending(path: book.coverFileName))
        #expect(FileManager.default.fileExists(atPath: model.coverURL(for: book).path))
        #expect(model.liveProgress.isEmpty)
        #expect(model.failureAlert == nil)
    }

    @Test("a failing Import sets the failure alert and keeps the Import item")
    func failure() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model
        let task = try await startModel(model)
        defer { task.cancel() }

        let source = fixture.root.appending(path: "Notes", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("not a Page".utf8).write(to: source.appending(path: "readme.txt"))
        await model.importSource(source)

        try await waitUntil("the failure alert is set") { model.failureAlert != nil }
        let alert = try #require(model.failureAlert)
        #expect(alert.sourceName == "Notes")
        #expect(alert.reason == .noImagesFound)

        try await waitUntil("the Failed Import is the only item") {
            if model.items.count == 1, case .importRecord(let record) = model.items[0] {
                return record.status == .failed
            }
            return false
        }
        guard case .importRecord(let record) = model.items[0] else { return }
        #expect(record.id == alert.id)
        #expect(model.liveProgress[alert.id] == nil)
    }

    @Test("open does not reorder items until reload") func openNoReorder() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model
        let task = try await startModel(model)
        defer { task.cancel() }

        let older = try makeImageSource(named: "Older", pageCount: 1, in: fixture.root)
        let newer = try makeImageSource(named: "Newer", pageCount: 1, in: fixture.root)
        await model.importSource(older)
        try await waitUntil("the older Book is in the Library") {
            books(in: model.items).map(\.title) == ["Older"]
        }
        await model.importSource(newer)
        try await waitUntil("both Books are in the Library, newest first") {
            model.items.count == 2 && books(in: model.items).map(\.title) == ["Newer", "Older"]
        }
        let before = model.items
        let olderBook = try #require(books(in: before).last)

        await model.open(olderBook.id)
        #expect(model.items == before)

        await model.reload()
        #expect(books(in: model.items).map(\.title) == ["Older", "Newer"])
        #expect(books(in: model.items).first?.lastOpenedAt != nil)
    }
}
