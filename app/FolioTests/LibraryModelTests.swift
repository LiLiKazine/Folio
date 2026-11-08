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

    /// Import storage that cannot read In Progress Imports but reads everything
    /// else, so only `Library.start()` and the model's reload fail; the scheduler,
    /// which reads Queued Imports, does not.
    private actor InProgressUnreadableImportRepository: ImportRepository {
        private let base = InMemoryImportRepository()

        func imports(status: ImportStatus) async throws -> [Import] {
            if status == .inProgress { throw RepositoryFailure() }
            return try await base.imports(status: status)
        }

        func importRecord(id: ImportID) async throws -> Import? {
            try await base.importRecord(id: id)
        }

        func add(_ record: Import) async throws { try await base.add(record) }
        func update(_ record: Import) async throws { try await base.update(record) }
        func remove(id: ImportID) async throws { try await base.remove(id: id) }
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

    /// Holds every Import inside `withAccess` until `open()` is called.
    private actor Gate {
        private var isOpen = false
        func open() { isOpen = true }
        func wait() async throws {
            while !isOpen { try await Task.sleep(for: .milliseconds(10)) }
        }
    }

    private struct GatedSourceAccess: SourceAccess {
        let gate: Gate

        func bookmark(for url: URL) throws(SourceAccessError) -> Data { Data(url.path.utf8) }

        func withAccess<T: Sendable>(
            to bookmark: Data, _ body: @Sendable (URL) async throws -> T
        ) async throws -> T {
            try await gate.wait()
            return try await body(URL(fileURLWithPath: String(decoding: bookmark, as: UTF8.self)))
        }
    }

    /// Import storage whose read of In Progress Imports waits for `gate`, so
    /// `Library.start()` stays in flight until the test opens it.
    private actor GatedImportRepository: ImportRepository {
        private let base = InMemoryImportRepository()
        let gate: Gate

        init(gate: Gate) { self.gate = gate }

        func imports(status: ImportStatus) async throws -> [Import] {
            if status == .inProgress { try await gate.wait() }
            return try await base.imports(status: status)
        }

        func importRecord(id: ImportID) async throws -> Import? {
            try await base.importRecord(id: id)
        }

        func add(_ record: Import) async throws { try await base.add(record) }
        func update(_ record: Import) async throws { try await base.update(record) }
        func remove(id: ImportID) async throws { try await base.remove(id: id) }
    }

    private func makeFixture(
        books: any BookRepository = InMemoryBookRepository(),
        imports: any ImportRepository = InMemoryImportRepository(),
        sourceAccess: any SourceAccess = InMemorySourceAccess()
    ) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "LibraryModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let booksDirectory = root.appending(path: "Books", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: booksDirectory, withIntermediateDirectories: true)
        let library = Library(
            books: books, imports: imports,
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

    /// The title and message of each queued Notice, in order.
    private func copy(of notices: [Notice]) -> [[String]] {
        notices.map { [$0.title, $0.message] }
    }

    private func copy(of notice: Notice) -> [String] {
        [notice.title, notice.message]
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
        #expect(model.notices.isEmpty)
    }

    @Test("a failing Import queues its Notice and keeps the Import item")
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

        try await waitUntil("the Notice is queued") { model.presentedNotice != nil }
        let notice = try #require(model.presentedNotice)
        #expect(copy(of: notice) == ["Couldn't Import “Notes”", "No images found"])

        try await waitUntil("the Failed Import is the only item") {
            if model.items.count == 1, case .importRecord(let record) = model.items[0] {
                return record.status == .failed
            }
            return false
        }
        guard case .importRecord(let record) = model.items[0] else { return }
        #expect(record.sourceName == "Notes")
        #expect(record.failureReason == .noImagesFound)
        #expect(model.liveProgress[record.id] == nil)
    }

    @Test("a failing Import with a failing reload yields only the Import's Notice")
    func failureWithFailingReload() async throws {
        let gate = Gate()
        let bookRepository = FailingBookRepository()
        let fixture = try makeFixture(
            books: bookRepository, sourceAccess: GatedSourceAccess(gate: gate))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model
        let task = try await startModel(model)
        defer { task.cancel() }

        let source = fixture.root.appending(path: "Notes", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("not a Page".utf8).write(to: source.appending(path: "readme.txt"))
        await model.importSource(source)
        try await waitUntil("the ImportQueued event is handled") { model.handledEventCount == 1 }
        // From here every reload fails; the Import then fails with no images found.
        await bookRepository.fail([.allBooks])
        await gate.open()

        try await waitUntil("the ImportFailed event is handled") { model.handledEventCount == 2 }
        #expect(copy(of: model.notices) == [["Couldn't Import “Notes”", "No images found"]])
    }

    @Test("cancel yields no Notice and keeps the Failed item")
    func cancelNoNotice() async throws {
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

        #expect(model.notices.isEmpty)
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

    // MARK: - Notices

    @Test("an unavailable Source on import yields a Notice naming it")
    func importUnavailableNotice() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "LibraryModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let source = root.appending(path: "Vol 3", directoryHint: .isDirectory)
        var sourceAccess = InMemorySourceAccess()
        sourceAccess.unbookmarkable = [source.path]
        let fixture = try makeFixture(sourceAccess: sourceAccess)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model

        await model.importSource(source)

        #expect(
            copy(of: model.notices) == [
                [
                    "Couldn't Import “Vol 3”",
                    "Folio couldn't open the folder or zip. Pick it again from the file picker.",
                ]
            ])
    }

    @Test("a failing rename write yields a storage Notice for Rename")
    func renameStorageNotice() async throws {
        let bookRepository = FailingBookRepository()
        let fixture = try makeFixture(books: bookRepository)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model
        let task = try await startModel(model)
        defer { task.cancel() }
        await model.importSource(
            try makeImageSource(named: "Vol 1", pageCount: 1, in: fixture.root))
        try await waitUntil("the Book is in the Library") { books(in: model.items).count == 1 }
        let book = try #require(books(in: model.items).first)

        await bookRepository.fail([.update])
        await model.rename(book.id, to: "Volume One")

        #expect(
            copy(of: model.notices) == [
                [
                    "Couldn't Rename",
                    "Folio couldn't save the change. Try again; if it keeps happening, relaunch Folio.",
                ]
            ])
    }

    /// One user operation and the single repository write it depends on.
    struct WriteFailure: Sendable, CustomTestStringConvertible {
        let operation: LibraryOperation
        let failsImports: Bool
        let call: RepositoryCall
        /// The Notice title, spelled out rather than built from `operation`.
        let title: String
        var testDescription: String { title }
    }

    @Test(
        "a failing repository write yields the operation's Couldn't Notice",
        arguments: [
            WriteFailure(
                operation: .import, failsImports: true, call: .add, title: "Couldn't Import"),
            WriteFailure(
                operation: .cancelImport, failsImports: true, call: .update,
                title: "Couldn't Cancel Import"),
            WriteFailure(
                operation: .retryImport, failsImports: true, call: .update,
                title: "Couldn't Retry Import"),
            WriteFailure(
                operation: .removeImport, failsImports: true, call: .remove,
                title: "Couldn't Remove Import"),
            WriteFailure(
                operation: .rename, failsImports: false, call: .update, title: "Couldn't Rename"),
            WriteFailure(
                operation: .open, failsImports: false, call: .update, title: "Couldn't Open"),
            WriteFailure(
                operation: .deleteBook, failsImports: false, call: .remove,
                title: "Couldn't Delete Book"),
        ])
    func writeFailureNotice(_ failure: WriteFailure) async throws {
        let bookID = BookID()
        let book = Book(
            id: bookID, title: "Vol 1", folderName: bookID.rawValue.uuidString,
            pages: [Page(fileName: "0001.png")], coverFileName: CoverImage.fileName,
            importedAt: .now, lastOpenedAt: nil, readingPosition: nil)
        func importRecord(_ status: ImportStatus) -> Import {
            Import(
                id: ImportID(), status: status, sourceBookmark: Data(), sourceName: "Vol 2",
                title: "Vol 2", pagesDone: 0, pagesTotal: nil,
                failureReason: status == .failed ? .noImagesFound : nil, bookID: nil,
                createdAt: .now, finishedAt: status == .failed ? .now : nil)
        }
        let queued = importRecord(.queued)
        let failed = importRecord(.failed)
        let bookRepository = FailingBookRepository()
        let importRepository = FailingImportRepository()
        try await bookRepository.add(book)
        try await importRepository.add(queued)
        try await importRepository.add(failed)
        // The model is not started, so no Import scheduler runs the Queued Import.
        let fixture = try makeFixture(books: bookRepository, imports: importRepository)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model
        if failure.failsImports {
            await importRepository.fail([failure.call])
        } else {
            await bookRepository.fail([failure.call])
        }

        switch failure.operation {
        case .import:
            await model.importSource(
                fixture.root.appending(path: "Vol 3", directoryHint: .isDirectory))
        case .cancelImport: await model.cancelImport(queued.id)
        case .retryImport: await model.retryImport(failed.id)
        case .removeImport: await model.removeImport(failed.id)
        case .rename: await model.rename(book.id, to: "Volume One")
        case .open: await model.open(book.id)
        case .deleteBook: await model.removeBook(book.id)
        case .updateLibrary, .openLibrary:
            Issue.record("No operation set up for \(failure.operation.rawValue)")
        }

        #expect(
            copy(of: model.notices) == [
                [
                    failure.title,
                    "Folio couldn't save the change. Try again; if it keeps happening, relaunch Folio.",
                ]
            ])
    }

    @Test("two failures queue two Notices in order; dismiss shows the second")
    func noticesQueue() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model

        await model.rename(BookID(), to: "  ")
        await model.rename(BookID(), to: "Missing")

        let first = ["Couldn't Rename", "A Book needs a Title."]
        let second = ["Couldn't Rename", "It's no longer in the Library."]
        #expect(copy(of: model.notices) == [first, second])
        #expect(model.presentedNotice.map(copy(of:)) == first)
        let firstID = try #require(model.presentedNotice).id
        model.dismissNotice(firstID)
        #expect(model.presentedNotice.map(copy(of:)) == second)
        // Dismissing the first again is stale and leaves the second waiting.
        model.dismissNotice(firstID)
        #expect(model.presentedNotice.map(copy(of:)) == second)
        model.dismissNotice(try #require(model.presentedNotice).id)
        #expect(model.presentedNotice == nil)
    }

    @Test("a repeat of the last Notice is not queued again") func noticeRepeat() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model

        await model.rename(BookID(), to: "")
        await model.rename(BookID(), to: "")
        await model.rename(BookID(), to: "Missing")
        await model.rename(BookID(), to: "")

        #expect(
            copy(of: model.notices).map { $0[1] } == [
                "A Book needs a Title.", "It's no longer in the Library.", "A Book needs a Title.",
            ])
    }

    @Test("items() read failure yields Update the Library") func reloadNotice() async throws {
        let bookRepository = FailingBookRepository()
        let fixture = try makeFixture(books: bookRepository)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model
        let task = try await startModel(model)
        defer { task.cancel() }
        #expect(model.notices.isEmpty)

        await bookRepository.fail([.allBooks])
        await model.reload()

        #expect(
            copy(of: model.notices) == [
                [
                    "Couldn't Update the Library",
                    "Folio couldn't save the change. What you see may be out of date; relaunch Folio to refresh.",
                ]
            ])
    }

    @Test("libraryStorageFailed event yields its Notice") func storageEventNotice() async throws {
        let imports = FailingImportRepository()
        let fixture = try makeFixture(imports: imports)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model
        let task = try await startModel(model)
        defer { task.cancel() }

        // The Import is saved, but the scheduler cannot read the queue.
        await imports.fail([.imports])
        await model.importSource(
            try makeImageSource(named: "Vol 1", pageCount: 1, in: fixture.root))

        let expected = [
            "Couldn't Update the Library",
            "Folio couldn't save the change. What you see may be out of date; relaunch Folio to refresh.",
        ]
        try await waitUntil("the LibraryStorageFailed Notice is queued") {
            copy(of: model.notices).contains(expected)
        }
    }

    @Test("start recovery failure yields Open the Library through the event")
    func startNotice() async throws {
        let base = InMemoryImportRepository()
        try await base.add(
            Import(
                id: ImportID(), status: .inProgress, sourceBookmark: Data("/gone".utf8),
                sourceName: "Gone", title: "Gone", pagesDone: 1, pagesTotal: 2,
                failureReason: nil, bookID: nil, createdAt: .now, finishedAt: nil))
        let imports = FailingImportRepository(base: base)
        await imports.fail([.update])
        let fixture = try makeFixture(imports: imports)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model
        let task = try await startModel(model)
        defer { task.cancel() }

        let expected = [
            "Couldn't Open the Library",
            "Folio couldn't open its Library. Relaunch Folio; if it keeps happening, free up storage.",
        ]
        try await waitUntil("the Open the Library Notice is queued") { !model.notices.isEmpty }
        #expect(copy(of: model.notices) == [expected])
    }

    @Test("start failing to read In Progress Imports yields Open the Library and nothing else")
    func startThrowsNotice() async throws {
        let fixture = try makeFixture(imports: InProgressUnreadableImportRepository())
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model
        let task = try await startModel(model)
        defer { task.cancel() }

        // The reload that follows reads In Progress Imports too and also fails, but
        // one failure at launch is one Notice.
        #expect(
            copy(of: model.notices) == [
                [
                    "Couldn't Open the Library",
                    "Folio couldn't open its Library. Relaunch Folio; if it keeps happening, free up storage.",
                ]
            ])
    }

    @Test("a broken store at launch yields Open the Library and Update the Library, once each")
    func brokenStoreAtLaunch() async throws {
        let imports = FailingImportRepository()
        await imports.fail([.imports])
        let fixture = try makeFixture(imports: imports)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model
        let task = try await startModel(model)
        defer { task.cancel() }

        // Two failures the user is told about: the Library could not open, and the
        // Import queue could not be read (LibraryStorageFailed). The reloads after
        // each also fail, but add no Notice of their own.
        try await waitUntil("the queue failure is handled") { model.handledEventCount >= 1 }
        #expect(
            copy(of: model.notices) == [
                [
                    "Couldn't Open the Library",
                    "Folio couldn't open its Library. Relaunch Folio; if it keeps happening, free up storage.",
                ],
                [
                    "Couldn't Update the Library",
                    "Folio couldn't save the change. What you see may be out of date; relaunch Folio to refresh.",
                ],
            ])
    }

    @Test("reload before start() has loaded does nothing")
    func reloadBeforeStart() async throws {
        let gate = Gate()
        let bookRepository = FailingBookRepository()
        let bookID = BookID()
        try await bookRepository.add(
            Book(
                id: bookID, title: "Vol 1", folderName: bookID.rawValue.uuidString,
                pages: [Page(fileName: "0001.png")], coverFileName: CoverImage.fileName,
                importedAt: .now, lastOpenedAt: nil, readingPosition: nil))
        let fixture = try makeFixture(
            books: bookRepository, imports: GatedImportRepository(gate: gate))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model
        let task = Task { await model.start() }
        defer { task.cancel() }

        // start() is held in the launch step; a reload now would read a broken store.
        await bookRepository.fail([.allBooks])
        await model.reload()

        #expect(model.notices.isEmpty)
        #expect(model.items.isEmpty)
        #expect(!model.isLoaded)
        await gate.open()
    }

    @Test("a file picker failure queues exactly its Notice") func filePickerFailed() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model

        model.filePickerFailed()

        #expect(
            copy(of: model.notices) == [
                ["Couldn't Import", "Folio couldn't open the file picker. Try again."]
            ])
    }
}
