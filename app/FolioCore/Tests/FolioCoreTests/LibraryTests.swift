import Foundation
import Testing

@testable import FolioCore

@Suite("Library")
struct LibraryTests {
    private struct EventTimeout: Error {}

    /// Source access whose `withAccess` signals `entered`, then holds until its task is
    /// cancelled before running `body`, so a test can cancel an Import mid-pipeline.
    private struct HeldSourceAccess: SourceAccess {
        let entered: AsyncStream<Void>.Continuation

        func bookmark(for url: URL) throws(SourceAccessError) -> Data { Data(url.path.utf8) }

        func withAccess<T: Sendable>(
            to bookmark: Data, _ body: @Sendable (URL) async throws -> T
        ) async throws -> T {
            entered.yield()
            try? await Task.sleep(for: .seconds(60))
            return try await body(URL(fileURLWithPath: String(decoding: bookmark, as: UTF8.self)))
        }
    }

    private struct Fixture {
        let directory: TemporaryDirectory
        let booksDirectory: URL
        let books = InMemoryBookRepository()
        let imports = InMemoryImportRepository()
        let library: Library

        init(
            sourceAccess: any SourceAccess = InMemorySourceAccess(),
            now: @escaping @Sendable () -> Date = { .now }
        ) throws {
            directory = try TemporaryDirectory()
            booksDirectory = directory.url.appending(path: "Books", directoryHint: .isDirectory)
            library = Library(
                books: books, imports: imports,
                pipeline: ImportPipeline(
                    booksDirectory: booksDirectory,
                    storage: FixedStorageCapacity(bytes: .max)),
                sourceAccess: sourceAccess, now: now)
        }

        /// A folder Source named `name` holding `pageCount` real PNG images.
        func folderSource(_ name: String = "Source", pageCount: Int = 2) throws -> URL {
            let source = directory.url.appending(path: name, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            for index in 0..<pageCount {
                try ImageFixtures.png(
                    width: 40, height: 60, at: source.appending(path: "\(index + 1).png"))
            }
            return source
        }

        /// Names under the Books directory, plus `.staging/<name>` for anything staged.
        func booksDirectoryContents() throws -> [String] {
            let manager = FileManager.default
            let staging = booksDirectory.appending(path: ".staging")
            let top = try manager.contentsOfDirectory(atPath: booksDirectory.path)
            let staged = (try? manager.contentsOfDirectory(atPath: staging.path)) ?? []
            return (top.filter { $0 != ".staging" } + staged.map { ".staging/\($0)" }).sorted()
        }

        /// Drains `library.events` until one satisfies `done`, failing after 5 s.
        func events(
            until done: @escaping @Sendable (LibraryEvent) -> Bool,
            onEach: @escaping @Sendable (LibraryEvent) async throws -> Void = { _ in }
        ) async throws -> [LibraryEvent] {
            let stream = library.events
            return try await withTimeout {
                var seen: [LibraryEvent] = []
                for await event in stream {
                    seen.append(event)
                    try await onEach(event)
                    if done(event) { return seen }
                }
                throw EventTimeout()
            }
        }
    }

    private static func withTimeout<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                throw EventTimeout()
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw EventTimeout() }
            return result
        }
    }

    private static func isCompleted(_ event: LibraryEvent) -> Bool {
        if case .importCompleted = event { return true }
        return false
    }

    private static func isFailed(_ event: LibraryEvent) -> Bool {
        if case .importFailed = event { return true }
        return false
    }

    private static func book(id: BookID = BookID(), importedAt: Date) -> Book {
        Book(
            id: id, title: "Book", folderName: id.rawValue.uuidString,
            pages: [Page(fileName: "0001.png")],
            coverFileName: CoverImage.fileName, importedAt: importedAt, lastOpenedAt: nil,
            readingPosition: nil)
    }

    private static func importRecord(
        status: ImportStatus, createdAt: Date, bookmark: Data = Data()
    ) -> Import {
        Import(
            id: ImportID(), status: status, sourceBookmark: bookmark, sourceName: "Source",
            title: "Source", pagesDone: 0, pagesTotal: nil,
            failureReason: status == .failed ? .noImagesFound : nil, bookID: nil,
            createdAt: createdAt, finishedAt: nil)
    }

    /// Creates an Import from a two-Page Source and waits for it to complete.
    private static func importedBook(in fixture: Fixture) async throws -> Book {
        _ = try await fixture.library.createImport(from: try fixture.folderSource())
        let events = try await fixture.events(until: isCompleted)
        guard case .importCompleted(_, let book) = events.last else { throw EventTimeout() }
        return book
    }

    @Test("createImport queues, then completes into a Book")
    func happyPath() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        try await fixture.library.start()

        let id = try await fixture.library.createImport(from: try fixture.folderSource())
        let events = try await fixture.events(until: Self.isCompleted)

        guard case .importCompleted(let completedID, let book) = events.last else {
            Issue.record("no importCompleted in \(events)")
            return
        }
        #expect(completedID == id)
        #expect(
            events == [
                .importQueued(id, title: "Source"),
                .importStarted(id, pagesTotal: 2),
                .importProgressed(id, pagesDone: 1, pagesTotal: 2),
                .importProgressed(id, pagesDone: 2, pagesTotal: 2),
                .importCompleted(id, book),
            ])
        #expect(book.title == "Source")
        #expect(book.folderName == book.id.rawValue.uuidString)
        #expect(try await fixture.library.items() == [.book(book)])
        let completed = try await fixture.imports.imports(status: .completed)
        #expect(completed.count == 1)
        #expect(completed.first?.id == id)
        #expect(completed.first?.bookID == book.id)
        #expect(completed.first?.pagesDone == 2)
        #expect(completed.first?.finishedAt != nil)
        #expect(try await fixture.books.allBooks() == [book])
    }

    @Test("two Imports run serially, never both In Progress")
    func serial() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        try await fixture.library.start()

        let first = try await fixture.library.createImport(
            from: try fixture.folderSource("First", pageCount: 3))
        let second = try await fixture.library.createImport(
            from: try fixture.folderSource("Second", pageCount: 3))
        let imports = fixture.imports
        let events = try await fixture.events(
            until: { if case .importCompleted(second, _) = $0 { true } else { false } },
            onEach: { _ throws in
                let inProgress = try await imports.imports(status: .inProgress)
                #expect(inProgress.count <= 1)
            })

        let completedOrder = events.compactMap { event -> ImportID? in
            if case .importCompleted(let id, _) = event { id } else { nil }
        }
        #expect(completedOrder == [first, second])
        let firstCompleted = events.firstIndex {
            if case .importCompleted(first, _) = $0 { true } else { false }
        }
        let secondStarted = events.firstIndex { $0 == .importStarted(second, pagesTotal: 3) }
        #expect(firstCompleted != nil && secondStarted != nil && firstCompleted! < secondStarted!)
        #expect(try await fixture.imports.imports(status: .completed).count == 2)
    }

    @Test("failure records reason and keeps the Import")
    func failure() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        try await fixture.library.start()

        let id = try await fixture.library.createImport(
            from: try fixture.folderSource("Empty", pageCount: 0))
        let events = try await fixture.events(until: Self.isFailed)

        #expect(events.last == .importFailed(id, sourceName: "Empty", reason: .noImagesFound))
        let failed = try #require(try await fixture.imports.importRecord(id: id))
        #expect(failed.status == .failed)
        #expect(failed.failureReason == .noImagesFound)
        #expect(failed.finishedAt != nil)
        #expect(failed.bookID == nil)
        #expect(try await fixture.library.items() == [.importRecord(failed)])
        #expect(try fixture.booksDirectoryContents() == [])
    }

    @Test("retry re-queues under the same id and can complete")
    func retry() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        try await fixture.library.start()
        let source = try fixture.folderSource("Later", pageCount: 0)
        let id = try await fixture.library.createImport(from: source)
        _ = try await fixture.events(until: Self.isFailed)

        try ImageFixtures.png(width: 40, height: 60, at: source.appending(path: "1.png"))
        try await fixture.library.retryImport(id: id)
        let events = try await fixture.events(until: Self.isCompleted)

        #expect(events.first == .importQueued(id, title: "Later"))
        guard case .importCompleted(let completedID, let book) = events.last else {
            Issue.record("no importCompleted in \(events)")
            return
        }
        #expect(completedID == id)
        let record = try #require(try await fixture.imports.importRecord(id: id))
        #expect(record.status == .completed)
        #expect(record.failureReason == nil)
        #expect(record.bookID == book.id)
        #expect(try await fixture.library.items() == [.book(book)])
    }

    @Test("cancel while In Progress fails with cancelled and leaves no Book")
    func cancel() async throws {
        let (entered, enteredContinuation) = AsyncStream.makeStream(of: Void.self)
        let fixture = try Fixture(sourceAccess: HeldSourceAccess(entered: enteredContinuation))
        defer { fixture.directory.remove() }
        try await fixture.library.start()

        let id = try await fixture.library.createImport(from: try fixture.folderSource())
        try await Self.withTimeout {
            for await _ in entered { return }
            throw EventTimeout()
        }
        #expect(try await fixture.imports.importRecord(id: id)?.status == .inProgress)
        try await fixture.library.cancelImport(id: id)
        let events = try await fixture.events(until: Self.isFailed)

        #expect(events.last == .importFailed(id, sourceName: "Source", reason: .cancelled))
        #expect(try await fixture.imports.importRecord(id: id)?.status == .failed)
        #expect(try await fixture.books.allBooks() == [])
        #expect(try fixture.booksDirectoryContents() == [])
    }

    @Test("cancel while Queued fails with cancelled")
    func cancelQueued() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        let queued = Self.importRecord(status: .queued, createdAt: .now)
        try await fixture.imports.add(queued)

        try await fixture.library.cancelImport(id: queued.id)
        let events = try await fixture.events(until: Self.isFailed)

        #expect(events == [.importFailed(queued.id, sourceName: "Source", reason: .cancelled)])
        let record = try #require(try await fixture.imports.importRecord(id: queued.id))
        #expect(record.status == .failed)
        #expect(record.failureReason == .cancelled)
        await #expect(throws: LibraryError.invalidStatus) {
            try await fixture.library.cancelImport(id: queued.id)
        }
    }

    @Test("removeImport only works on Failed")
    func removeImport() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        let queued = Self.importRecord(status: .queued, createdAt: .now)
        let failed = Self.importRecord(status: .failed, createdAt: .now)
        try await fixture.imports.add(queued)
        try await fixture.imports.add(failed)

        await #expect(throws: LibraryError.invalidStatus) {
            try await fixture.library.removeImport(id: queued.id)
        }
        await #expect(throws: LibraryError.notFound) {
            try await fixture.library.removeImport(id: ImportID())
        }
        try await fixture.library.removeImport(id: failed.id)
        let events = try await fixture.events(until: { _ in true })

        #expect(events == [.importRemoved(failed.id)])
        #expect(try await fixture.imports.importRecord(id: failed.id) == nil)
        #expect(try await fixture.imports.importRecord(id: queued.id) == queued)
    }

    @Test("rename rejects empty Title")
    func renameEmpty() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        let book = Self.book(importedAt: .now)
        try await fixture.books.add(book)

        await #expect(throws: LibraryError.emptyTitle) {
            try await fixture.library.rename(bookID: book.id, to: "  \n ")
        }
        try await fixture.library.rename(bookID: book.id, to: "  Vol.3 ")
        let events = try await fixture.events(until: { _ in true })

        #expect(events == [.bookRenamed(book.id, title: "Vol.3")])
        #expect(try await fixture.books.book(id: book.id)?.title == "Vol.3")
    }

    @Test("open sets lastOpenedAt and emits bookOpened")
    func open() async throws {
        let openedAt = Date(timeIntervalSince1970: 1_000_000)
        let fixture = try Fixture(now: { openedAt })
        defer { fixture.directory.remove() }
        let book = Self.book(importedAt: .distantPast)
        try await fixture.books.add(book)

        try await fixture.library.open(bookID: book.id)
        let events = try await fixture.events(until: { _ in true })

        #expect(events == [.bookOpened(book.id, at: openedAt)])
        #expect(try await fixture.books.book(id: book.id)?.lastOpenedAt == openedAt)
        await #expect(throws: LibraryError.notFound) {
            try await fixture.library.open(bookID: BookID())
        }
    }

    @Test("removeBook deletes folder and record")
    func removeBook() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        try await fixture.library.start()
        let book = try await Self.importedBook(in: fixture)
        #expect(try fixture.booksDirectoryContents() == [book.folderName])

        try await fixture.library.removeBook(id: book.id)
        let events = try await fixture.events(until: { _ in true })

        #expect(events == [.bookRemoved(book.id)])
        #expect(try fixture.booksDirectoryContents() == [])
        #expect(try await fixture.books.allBooks() == [])
    }

    @Test("start returns In Progress to Queued and runs it")
    func recovery() async throws {
        let access = InMemorySourceAccess()
        let fixture = try Fixture(sourceAccess: access)
        defer { fixture.directory.remove() }
        let source = try fixture.folderSource()
        var interrupted = Self.importRecord(
            status: .inProgress, createdAt: .now, bookmark: try access.bookmark(for: source))
        interrupted.pagesDone = 1
        interrupted.pagesTotal = 2
        try await fixture.imports.add(interrupted)
        try fixture.directory.file("Books/.staging/\(UUID().uuidString)/pages/0001.png")

        try await fixture.library.start()
        let events = try await fixture.events(until: Self.isCompleted)

        #expect(events.first == .importStarted(interrupted.id, pagesTotal: 2))
        guard case .importCompleted(let id, let book) = events.last else {
            Issue.record("no importCompleted in \(events)")
            return
        }
        #expect(id == interrupted.id)
        #expect(try await fixture.imports.importRecord(id: id)?.status == .completed)
        #expect(try fixture.booksDirectoryContents() == [book.folderName])
    }

    @Test("start removes Book records without folders and folders without records")
    func reconcile() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        let kept = Self.book(importedAt: .now)
        let missingFolder = Self.book(importedAt: .now)
        try await fixture.books.add(kept)
        try await fixture.books.add(missingFolder)
        try fixture.directory.file("Books/\(kept.folderName)/pages/0001.png")
        let orphan = UUID().uuidString
        try fixture.directory.file("Books/\(orphan)/pages/0001.png")
        try fixture.directory.file("Books/Library.store")
        try fixture.directory.file("Books/Notes/readme.txt")

        try await fixture.library.start()

        #expect(try await fixture.books.allBooks() == [kept])
        #expect(
            try fixture.booksDirectoryContents()
                == ["Library.store", "Notes", kept.folderName].sorted())
    }

    @Test("items are ordered In Progress, Queued, Failed, then Books")
    func itemOrder() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        let base = Date(timeIntervalSince1970: 1_000_000)
        let inProgress = Self.importRecord(status: .inProgress, createdAt: base)
        let laterQueued = Self.importRecord(status: .queued, createdAt: base + 20)
        let earlierQueued = Self.importRecord(status: .queued, createdAt: base + 10)
        let laterFailed = Self.importRecord(status: .failed, createdAt: base + 40)
        let earlierFailed = Self.importRecord(status: .failed, createdAt: base + 30)
        let completed = Self.importRecord(status: .completed, createdAt: base + 50)
        for record in [
            laterFailed, completed, laterQueued, inProgress, earlierFailed, earlierQueued,
        ] {
            try await fixture.imports.add(record)
        }
        let olderBook = Self.book(importedAt: base)
        var openedBook = Self.book(importedAt: base - 100)
        openedBook.lastOpenedAt = base + 100
        try await fixture.books.add(olderBook)
        try await fixture.books.add(openedBook)

        let items = try await fixture.library.items()

        #expect(
            items == [
                .importRecord(inProgress), .importRecord(earlierQueued), .importRecord(laterQueued),
                .importRecord(earlierFailed), .importRecord(laterFailed),
                .book(openedBook), .book(olderBook),
            ])
        #expect(items.map(\.id).first == "import:\(inProgress.id.rawValue.uuidString)")
        #expect(items.map(\.id).last == "book:\(olderBook.id.rawValue.uuidString)")
    }

    @Test("unavailable Source fails with sourceUnavailable")
    func unavailable() async throws {
        var access = InMemorySourceAccess()
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let source = directory.url.appending(path: "Gone", directoryHint: .isDirectory)
        access.unavailable = [source.path]
        let fixture = try Fixture(sourceAccess: access)
        defer { fixture.directory.remove() }
        try await fixture.library.start()

        let id = try await fixture.library.createImport(from: source)
        let events = try await fixture.events(until: Self.isFailed)

        #expect(events.last == .importFailed(id, sourceName: "Gone", reason: .sourceUnavailable))
        #expect(try await fixture.library.items().map(\.id) == ["import:\(id.rawValue.uuidString)"])
    }
}
