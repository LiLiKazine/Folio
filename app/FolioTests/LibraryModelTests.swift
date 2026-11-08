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
        let library: Library
        let model: LibraryModel
    }

    /// Source access that holds every Import inside `withAccess` until its task is
    /// cancelled, so the first Import stays In Progress and later ones stay Queued.
    private struct HeldSourceAccess: SourceAccess {
        func bookmark(for url: URL) throws(SourceAccessError) -> Data { Data(url.path.utf8) }

        func withAccess<T: Sendable>(
            to bookmark: Data, _ body: @Sendable (URL) async throws -> T
        ) async throws -> T {
            try await Task.sleep(for: .seconds(60))
            return try await body(URL(fileURLWithPath: String(decoding: bookmark, as: UTF8.self)))
        }
    }

    private func makeFixture(
        sourceAccess: any SourceAccess = InMemorySourceAccess()
    ) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "LibraryModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let booksDirectory = root.appending(path: "Books", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: booksDirectory, withIntermediateDirectories: true)
        let library = Library(
            books: InMemoryBookRepository(), imports: InMemoryImportRepository(),
            pipeline: ImportPipeline(booksDirectory: booksDirectory),
            sourceAccess: sourceAccess)
        return Fixture(
            root: root, booksDirectory: booksDirectory, library: library,
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
        _ condition: () async throws -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while try await !condition() {
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

    @Test("cancelling a Queued Import keeps the Failed item without an alert")
    func cancelNoAlert() async throws {
        let fixture = try makeFixture(sourceAccess: HeldSourceAccess())
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model
        let task = try await startModel(model)
        defer { task.cancel() }

        await model.importSource(try makeImageSource(named: "Held", pageCount: 1, in: fixture.root))
        await model.importSource(try makeImageSource(named: "Next", pageCount: 1, in: fixture.root))
        try await waitUntil("one Import is In Progress and one is Queued") {
            let statuses = try await fixture.library.items().compactMap { item -> ImportStatus? in
                if case .importRecord(let record) = item { record.status } else { nil }
            }
            return statuses == [.inProgress, .queued]
        }
        try await waitUntil("both ImportQueued events are handled") {
            model.handledEventCount == 2
        }
        await model.reload()
        guard case .importRecord(let running) = model.items[0],
            case .importRecord(let queued) = model.items[1]
        else {
            Issue.record("expected two Import items, got \(model.items)")
            return
        }
        defer { Task { await model.cancelImport(running.id) } }

        await model.cancelImport(queued.id)
        try await waitUntil("the ImportFailed event is handled") {
            model.handledEventCount == 3
        }

        #expect(model.failureAlert == nil)
        let failed = model.items.compactMap { item -> Import? in
            if case .importRecord(let record) = item, record.status == .failed {
                record
            } else {
                nil
            }
        }
        #expect(failed.map(\.id) == [queued.id])
        #expect(failed.first?.failureReason == .cancelled)
        #expect(model.liveProgress[queued.id] == nil)
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

        let handledBeforeOpen = model.handledEventCount
        await model.open(olderBook.id)

        try await waitUntil("the Library records the open") {
            try await fixture.library.items().contains {
                if case .book(let book) = $0 {
                    book.id == olderBook.id && book.lastOpenedAt != nil
                } else {
                    false
                }
            }
        }
        try await waitUntil("the model has handled the BookOpened event") {
            model.handledEventCount > handledBeforeOpen
        }
        #expect(model.items == before)

        await model.reload()
        #expect(books(in: model.items).map(\.title) == ["Older", "Newer"])
        #expect(books(in: model.items).first?.lastOpenedAt != nil)
    }
}
