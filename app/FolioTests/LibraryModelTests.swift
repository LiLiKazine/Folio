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

    /// Import storage whose first read of In Progress Imports fails and every later
    /// read succeeds, so `Library.start()` fails once and the reload after it works.
    private actor FirstInProgressReadFailsImportRepository: ImportRepository {
        private let base = InMemoryImportRepository()
        private var hasFailed = false

        func imports(status: ImportStatus) async throws -> [Import] {
            if status == .inProgress, !hasFailed {
                hasFailed = true
                throw RepositoryFailure()
            }
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
    /// A Source named `unheldSourceName` is not held.
    private struct HeldSourceAccess: SourceAccess {
        static let unheldSourceName = "Empty"

        func bookmark(for url: URL) throws(SourceAccessError) -> Data { Data(url.path.utf8) }

        func withAccess<T: Sendable>(
            to bookmark: Data, _ body: @Sendable (URL) async throws -> T
        ) async throws -> T {
            let url = URL(fileURLWithPath: String(decoding: bookmark, as: UTF8.self))
            if url.lastPathComponent != Self.unheldSourceName {
                try await Task.sleep(for: .seconds(60))
            }
            return try await body(url)
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
        libraryOrders: any LibraryOrderRepository = InMemoryLibraryOrderRepository(),
        sourceAccess: any SourceAccess = InMemorySourceAccess()
    ) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "LibraryModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let booksDirectory = root.appending(path: "Books", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: booksDirectory, withIntermediateDirectories: true)
        let library = Library(
            books: books, imports: imports, libraryOrders: libraryOrders,
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

    /// A folder Source named `name` with no images in it, so its Import fails.
    private func makeEmptySource(named name: String, in root: URL) throws -> URL {
        let source = root.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("not a Page".utf8).write(to: source.appending(path: "readme.txt"))
        return source
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

    /// A Book of `pageCount` Pages named 0001.png, 0002.png, and so on.
    private func makeBook(pageCount: Int = 1) -> Book {
        let id = BookID()
        return Book(
            id: id, title: "Vol 1", folderName: id.rawValue.uuidString,
            pages: (1...pageCount).map { Page(fileName: String(format: "%04d.png", $0)) },
            coverFileName: CoverImage.fileName, importedAt: .now, lastOpenedAt: nil,
            readingPosition: nil)
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

        // Each ImportQueued reload is the only one that can show that many items.
        await model.importSource(try makeEmptySource(named: "Notes", in: fixture.root))
        try await waitUntil("the Notes Import is an item") { model.items.count == 1 }
        await model.importSource(try makeEmptySource(named: "Later", in: fixture.root))
        try await waitUntil("both Imports are items") { model.items.count == 2 }
        // From here every reload fails; both Imports then fail with no images found,
        // Notes first. The events are handled in order, so once the Later Notice is
        // queued, the Notes ImportFailed event and its failing reload are done.
        await bookRepository.fail([.allBooks])
        await gate.open()

        try await waitUntil("the Later Import's Notice is queued") {
            model.notices.last.map(copy(of:)) == ["Couldn't Import “Later”", "No images found"]
        }
        #expect(
            copy(of: model.notices) == [
                ["Couldn't Import “Notes”", "No images found"],
                ["Couldn't Import “Later”", "No images found"],
            ])
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
        // The In Progress write emits no event, so reload rather than wait for one; a
        // reload still pending can only bring the same or newer state.
        try await waitUntil("the items show one Import In Progress and one Queued") {
            await model.reload()
            return model.items.compactMap { item -> ImportStatus? in
                if case .importRecord(let record) = item { record.status } else { nil }
            } == [.inProgress, .queued]
        }
        guard case .importRecord(let running) = model.items[0],
            case .importRecord(let queued) = model.items[1]
        else {
            Issue.record("expected two Import items, got \(model.items)")
            return
        }

        await model.cancelImport(queued.id)
        await model.cancelImport(running.id)
        // Imports run one at a time and events are handled in order, so once this
        // Import's Notice is queued, both cancellations have been handled; a Notice
        // for either would already be queued ahead of it.
        let empty = HeldSourceAccess.unheldSourceName
        await model.importSource(try makeEmptySource(named: empty, in: fixture.root))
        try await waitUntil("the \(empty) Import's Notice is queued") { !model.notices.isEmpty }
        #expect(copy(of: model.notices) == [["Couldn't Import “\(empty)”", "No images found"]])

        try await waitUntil("the items show the cancelled Import as Failed") {
            model.items.contains {
                if case .importRecord(let record) = $0 {
                    record.id == queued.id && record.status == .failed
                } else {
                    false
                }
            }
        }
        let cancelled = model.items.compactMap { item -> Import? in
            if case .importRecord(let record) = item, record.id == queued.id { record } else { nil }
        }
        #expect(cancelled.first?.failureReason == .cancelled)
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

        await model.open(olderBook)

        try await waitUntil("the Library records the open") {
            try await fixture.library.items().contains {
                if case .book(let book) = $0 {
                    book.id == olderBook.id && book.lastOpenedAt != nil
                } else {
                    false
                }
            }
        }
        // A bounded negative check: the BookOpened event changes no state, so nothing
        // marks it handled. Give a reload it might wrongly start 300 ms to land.
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.items == before)

        await model.reload()
        #expect(books(in: model.items).map(\.title) == ["Older", "Newer"])
        #expect(books(in: model.items).first?.lastOpenedAt != nil)
    }

    // MARK: - Reading

    @Test("open on a storage failure opens anyway with the Book it was given, and queues no Notice")
    func openStorageFailureOpens() async throws {
        let bookRepository = FailingBookRepository()
        let book = makeBook()
        try await bookRepository.add(book)
        let fixture = try makeFixture(books: bookRepository)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        await bookRepository.fail([.update])

        let shown = await fixture.model.open(book)

        #expect(shown == book)
        #expect(fixture.model.notices.isEmpty)
    }

    @Test("open on a missing Book does not open and queues Couldn't Open")
    func openMissingBook() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let shown = await fixture.model.open(makeBook())

        #expect(shown == nil)
        #expect(
            copy(of: fixture.model.notices) == [
                ["Couldn't Open", "It's no longer in the Library."]
            ]
        )
    }

    @Test("open shows the Reading Position the Library has, not the one on the card tapped")
    func openShowsCurrentPosition() async throws {
        let bookRepository = InMemoryBookRepository()
        var stored = makeBook(pageCount: 60)
        let onCard = stored  // the grid's copy, from before another window turned Pages
        stored.readingPosition = 49
        try await bookRepository.add(stored)
        let fixture = try makeFixture(books: bookRepository)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let shown = await fixture.model.open(onCard)

        #expect(onCard.readingPosition == nil)
        #expect(shown?.readingPosition == 49)
    }

    enum TurnPageFailure: CaseIterable, Sendable {
        case storageFails
        case bookIsGone
    }

    @Test("turnPage failures queue no Notice", arguments: TurnPageFailure.allCases)
    func turnPageFailureSilent(_ failure: TurnPageFailure) async throws {
        let bookRepository = FailingBookRepository()
        let book = makeBook(pageCount: 3)
        try await bookRepository.add(book)
        let fixture = try makeFixture(books: bookRepository)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let id: BookID
        switch failure {
        case .storageFails:
            await bookRepository.fail([.update])
            id = book.id
        case .bookIsGone:
            id = BookID()
        }

        await fixture.model.turnPage(id, to: 1)

        #expect(fixture.model.notices.isEmpty)
        #expect(try await bookRepository.book(id: book.id)?.readingPosition == nil)
    }

    @Test("choosing a Reading Mode whose save fails queues no Notice")
    func chooseReadingModeFailureQueuesNoNotice() async throws {
        let bookRepository = FailingBookRepository()
        let book = makeBook(pageCount: 3)
        try await bookRepository.add(book)
        let fixture = try makeFixture(books: bookRepository)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        await bookRepository.fail([.update])

        await fixture.model.chooseReadingMode(book.id, .vertical)

        #expect(fixture.model.notices.isEmpty)
        #expect(try await bookRepository.book(id: book.id)?.readingMode == .pageByPage)
    }

    /// A Book titled `title`, imported at `imported` seconds after the reference date.
    private func makeBook(titled title: String, imported: TimeInterval) -> Book {
        let id = BookID()
        return Book(
            id: id, title: title, folderName: id.rawValue.uuidString,
            pages: [Page(fileName: "0001.png")], coverFileName: CoverImage.fileName,
            importedAt: Date(timeIntervalSinceReferenceDate: imported), lastOpenedAt: nil,
            readingPosition: nil)
    }

    private func titles(of items: [LibraryItem]) -> [String] { books(in: items).map(\.title) }

    /// Adds a Book titled `title` to `repository` with a folder under the Books directory,
    /// so launch cleanup does not remove it as a record without a folder.
    private func addBook(
        titled title: String, imported: TimeInterval,
        to repository: any BookRepository, in fixture: Fixture
    ) async throws {
        let book = makeBook(titled: title, imported: imported)
        try FileManager.default.createDirectory(
            at: fixture.booksDirectory.appending(path: book.folderName),
            withIntermediateDirectories: true)
        try await repository.add(book)
    }

    @Test("choosing a Library Order reorders the items and updates libraryOrder")
    func chooseLibraryOrder() async throws {
        let bookRepository = InMemoryBookRepository()
        let fixture = try makeFixture(books: bookRepository)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await addBook(titled: "B", imported: 2, to: bookRepository, in: fixture)
        try await addBook(titled: "A", imported: 1, to: bookRepository, in: fixture)
        let model = fixture.model
        let task = try await startModel(model)
        defer { task.cancel() }
        #expect(titles(of: model.items) == ["B", "A"])

        let order = LibraryOrder(sort: .title, direction: .ascending)
        await model.chooseLibraryOrder(order)

        try await waitUntil("the items follow the Library Order") {
            titles(of: model.items) == ["A", "B"]
        }
        #expect(model.libraryOrder == order)
        #expect(model.notices.isEmpty)
    }

    @Test("the model starts with the Library Order that was saved")
    func startsWithSavedLibraryOrder() async throws {
        let bookRepository = InMemoryBookRepository()
        let libraryOrders = InMemoryLibraryOrderRepository()
        let saved = LibraryOrder(sort: .dateImported, direction: .ascending)
        try await libraryOrders.save(saved)
        let fixture = try makeFixture(books: bookRepository, libraryOrders: libraryOrders)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await addBook(titled: "B", imported: 2, to: bookRepository, in: fixture)
        try await addBook(titled: "A", imported: 1, to: bookRepository, in: fixture)
        let model = fixture.model
        #expect(model.libraryOrder == .initial)

        let task = try await startModel(model)
        defer { task.cancel() }

        #expect(model.libraryOrder == saved)
        #expect(titles(of: model.items) == ["A", "B"])
    }

    @Test("a Library Order that cannot be saved queues its Notice and changes nothing on screen")
    func chooseLibraryOrderFailureChangesNothing() async throws {
        let bookRepository = InMemoryBookRepository()
        let libraryOrders = FailingLibraryOrderRepository()
        let fixture = try makeFixture(books: bookRepository, libraryOrders: libraryOrders)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await addBook(titled: "B", imported: 2, to: bookRepository, in: fixture)
        try await addBook(titled: "A", imported: 1, to: bookRepository, in: fixture)
        let model = fixture.model
        let task = try await startModel(model)
        defer { task.cancel() }
        let itemsBefore = model.items
        await libraryOrders.fail([.saveLibraryOrder])

        await model.chooseLibraryOrder(LibraryOrder(sort: .title, direction: .ascending))

        #expect(
            copy(of: model.notices) == [
                [
                    "Couldn't Choose Library Order",
                    "Folio couldn't save the change. Try again; if it keeps happening, relaunch Folio.",
                ]
            ])
        #expect(model.libraryOrder == .initial)
        #expect(model.items == itemsBefore)
        #expect(titles(of: model.items) == ["B", "A"])
    }

    @Test("a burst of turns leaves the last position stored, with no Notice")
    func turnPageBurst() async throws {
        let bookRepository = InMemoryBookRepository()
        let book = makeBook(pageCount: 5)
        try await bookRepository.add(book)
        let fixture = try makeFixture(books: bookRepository)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        for index in [1, 2, 3, 4, 2] {
            await fixture.model.turnPage(book.id, to: index)
        }

        #expect(try await bookRepository.book(id: book.id)?.readingPosition == 2)
        #expect(fixture.model.notices.isEmpty)
    }

    /// Book storage whose save of a Book standing on Page 3 (index 2) is slow, so a later
    /// turn's save can finish before an earlier one's if nothing keeps them in order.
    private actor SlowFirstSaveBookRepository: BookRepository {
        private let base = InMemoryBookRepository()

        func allBooks() async throws -> [Book] { try await base.allBooks() }
        func book(id: BookID) async throws -> Book? { try await base.book(id: id) }
        func add(_ book: Book) async throws { try await base.add(book) }
        func remove(id: BookID) async throws { try await base.remove(id: id) }
        func update(_ book: Book) async throws {
            if book.readingPosition == 2 { try await Task.sleep(for: .milliseconds(300)) }
            try await base.update(book)
        }
    }

    @Test("turns started together leave the last Page stored even when an earlier save is slow")
    func turnPagesStayInOrder() async throws {
        let bookRepository = SlowFirstSaveBookRepository()
        let book = makeBook(pageCount: 5)
        try await bookRepository.add(book)
        let fixture = try makeFixture(books: bookRepository)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model

        let turns = [2, 3].map { index in Task { await model.turnPage(book.id, to: index) } }
        for turn in turns { await turn.value }
        try await waitUntil("the last turn is stored") {
            try await bookRepository.book(id: book.id)?.readingPosition == 3
        }
        // A bounded negative check: a slow earlier save must not land after it.
        try await Task.sleep(for: .milliseconds(500))

        #expect(try await bookRepository.book(id: book.id)?.readingPosition == 3)
        #expect(model.notices.isEmpty)
    }

    @Test("pageURL joins the Books directory, folder, pages folder, and Page file name")
    func pageURL() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let book = makeBook(pageCount: 2)

        #expect(
            fixture.model.pageURL(for: book, at: 1)
                == fixture.booksDirectory.appending(path: book.folderName)
                .appending(path: "pages").appending(path: "0002.png"))
    }

    @Test("removeBooks removes every Book it is given")
    func removeBooks() async throws {
        let bookRepository = InMemoryBookRepository()
        let books = [makeBook(), makeBook(), makeBook()]
        for book in books { try await bookRepository.add(book) }
        let fixture = try makeFixture(books: bookRepository)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        await fixture.model.removeBooks([books[0].id, books[2].id])

        #expect(try await bookRepository.book(id: books[0].id) == nil)
        #expect(try await bookRepository.book(id: books[1].id) != nil)
        #expect(try await bookRepository.book(id: books[2].id) == nil)
        #expect(fixture.model.notices.isEmpty)
    }

    @Test("removeBooks that cannot save queues the Couldn't Delete Book Notice")
    func removeBooksFailure() async throws {
        let bookRepository = FailingBookRepository()
        let book = makeBook()
        try await bookRepository.add(book)
        let fixture = try makeFixture(books: bookRepository)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        await bookRepository.fail([.remove])

        await fixture.model.removeBooks([book.id])

        #expect(copy(of: fixture.model.notices).map(\.first) == ["Couldn't Delete Book"])
        #expect(try await bookRepository.book(id: book.id) != nil)
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
        /// The repository the operation writes to.
        enum Store: Sendable { case books, imports, libraryOrders }
        let operation: LibraryOperation
        let store: Store
        let call: RepositoryCall
        /// The Notice title, spelled out rather than built from `operation`.
        let title: String
        var testDescription: String { title }
    }

    @Test(
        "a failing repository write yields the operation's Couldn't Notice",
        arguments: [
            WriteFailure(
                operation: .import, store: .imports, call: .add, title: "Couldn't Import"),
            WriteFailure(
                operation: .cancelImport, store: .imports, call: .update,
                title: "Couldn't Cancel Import"),
            WriteFailure(
                operation: .retryImport, store: .imports, call: .update,
                title: "Couldn't Retry Import"),
            WriteFailure(
                operation: .removeImport, store: .imports, call: .remove,
                title: "Couldn't Remove Import"),
            WriteFailure(
                operation: .rename, store: .books, call: .update, title: "Couldn't Rename"),
            WriteFailure(
                operation: .chooseLibraryOrder, store: .libraryOrders, call: .saveLibraryOrder,
                title: "Couldn't Choose Library Order"),
            WriteFailure(
                operation: .deleteBook, store: .books, call: .remove,
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
        let libraryOrderRepository = FailingLibraryOrderRepository()
        try await bookRepository.add(book)
        try await importRepository.add(queued)
        try await importRepository.add(failed)
        // The model is not started, so no Import scheduler runs the Queued Import.
        let fixture = try makeFixture(
            books: bookRepository, imports: importRepository,
            libraryOrders: libraryOrderRepository)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model
        switch failure.store {
        case .books: await bookRepository.fail([failure.call])
        case .imports: await importRepository.fail([failure.call])
        case .libraryOrders: await libraryOrderRepository.fail([failure.call])
        }

        switch failure.operation {
        case .import:
            await model.importSource(
                fixture.root.appending(path: "Vol 3", directoryHint: .isDirectory))
        case .cancelImport: await model.cancelImport(queued.id)
        case .retryImport: await model.retryImport(failed.id)
        case .removeImport: await model.removeImport(failed.id)
        case .rename: await model.rename(book.id, to: "Volume One")
        case .chooseLibraryOrder:
            await model.chooseLibraryOrder(LibraryOrder(sort: .title, direction: .ascending))
        case .deleteBook: await model.removeBook(book.id)
        case .open, .turnPage, .chooseReadingMode, .updateLibrary, .openLibrary:
            // Open, Turn Page and Choose Reading Mode are log-only (reading designs), so
            // they have no row here; their tests assert that no Notice appears.
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

    @Test("after a launch that could not start, the Library Order shown is the saved one")
    func libraryOrderAfterFailedStart() async throws {
        let bookRepository = InMemoryBookRepository()
        let libraryOrders = InMemoryLibraryOrderRepository()
        let saved = LibraryOrder(sort: .title, direction: .ascending)
        try await libraryOrders.save(saved)
        let fixture = try makeFixture(
            books: bookRepository, imports: FirstInProgressReadFailsImportRepository(),
            libraryOrders: libraryOrders)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await addBook(titled: "B", imported: 2, to: bookRepository, in: fixture)
        try await addBook(titled: "A", imported: 1, to: bookRepository, in: fixture)
        let model = fixture.model
        let task = try await startModel(model)
        defer { task.cancel() }

        // start() failed once, so the Library said so; the reload that followed worked,
        // so the grid and the Sort menu's ticks must agree on the saved Library Order.
        #expect(titles(of: model.items) == ["A", "B"])
        #expect(model.libraryOrder == saved)
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
        try await waitUntil("the queue failure's Notice is queued") { model.notices.count >= 2 }
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

    // MARK: - Notice kinds

    @Test("a failure with no action of the user's behind it is a status Notice")
    func storageFailedIsStatus() {
        let operations: [LibraryOperation] = [.openLibrary, .updateLibrary, .import, .deleteBook]
        for operation in operations {
            #expect(Notice(storageFailed: operation).kind == .status)
        }
    }

    @Test("a failure of an action the user took is a dialog Notice")
    func actionFailuresAreDialog() {
        let errors: [LibraryError] = [
            .sourceUnavailable(sourceName: "Vol 1"), .sourceNotDownloaded(sourceName: "Vol 1"),
            .emptyTitle, .notFound(.rename), .invalidStatus(.retryImport),
            .storage(.deleteBook), .storage(.openLibrary),
        ]
        for error in errors {
            #expect(Notice(error: error).kind == .dialog, "\(error)")
        }
        #expect(Notice(importFailed: "Vol 1", reason: .noImagesFound).kind == .dialog)
        #expect(Notice.filePickerFailed().kind == .dialog)
    }

    @Test("the status Notice and the dialog Notice are presented separately")
    func statusAndDialogPresentedSeparately() async throws {
        let bookRepository = FailingBookRepository()
        let fixture = try makeFixture(books: bookRepository)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model
        let task = try await startModel(model)
        defer { task.cancel() }

        // The status Notice is queued first.
        await bookRepository.fail([.allBooks])
        await model.reload()
        await model.rename(BookID(), to: "")

        let status = try #require(model.statusNotice)
        let dialog = try #require(model.presentedNotice)
        #expect(status.kind == .status)
        #expect(copy(of: status)[0] == "Couldn't Update the Library")
        #expect(dialog.kind == .dialog)
        #expect(copy(of: dialog) == ["Couldn't Rename", "A Book needs a Title."])

        // Dismissing one leaves the other; a stale id does nothing.
        model.dismissNotice(status.id)
        #expect(model.statusNotice == nil)
        #expect(model.presentedNotice == dialog)
        model.dismissNotice(status.id)
        #expect(model.presentedNotice == dialog)
        model.dismissNotice(dialog.id)
        #expect(model.presentedNotice == nil)
        #expect(model.notices.isEmpty)
    }

    @Test("with the kinds interleaved, only the Notice shown of each kind can be dismissed")
    func dismissInterleavedKinds() async throws {
        let fixture = try makeFixture(imports: InProgressUnreadableImportRepository())
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model
        let task = try await startModel(model)
        defer { task.cancel() }

        // Open the Library at launch, then a Rename, a failing reload, another Rename.
        await model.rename(BookID(), to: "")
        await model.reload()
        await model.rename(BookID(), to: "Missing")
        #expect(model.notices.map(\.kind) == [.status, .dialog, .status, .dialog])
        let status1 = model.notices[0]
        let dialog1 = model.notices[1]
        let status2 = model.notices[2]
        let dialog2 = model.notices[3]

        // The second of each kind is waiting, not shown, so dismissing it does nothing.
        model.dismissNotice(dialog2.id)
        model.dismissNotice(status2.id)
        #expect(model.notices == [status1, dialog1, status2, dialog2])

        model.dismissNotice(dialog1.id)
        #expect(model.presentedNotice == dialog2)
        #expect(model.statusNotice == status1)
        model.dismissNotice(status1.id)
        #expect(model.statusNotice == status2)
        #expect(model.notices == [status2, dialog2])
    }

    @Test("a repeat is collapsed against the last Notice of its kind")
    func collapseIsPerKind() async throws {
        let bookRepository = FailingBookRepository()
        let fixture = try makeFixture(books: bookRepository)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model
        let task = try await startModel(model)
        defer { task.cancel() }

        await bookRepository.fail([.allBooks])
        await model.reload()
        await model.rename(BookID(), to: "")
        await model.reload()

        #expect(
            copy(of: model.notices) == [
                [
                    "Couldn't Update the Library",
                    "Folio couldn't save the change. What you see may be out of date; relaunch Folio to refresh.",
                ],
                ["Couldn't Rename", "A Book needs a Title."],
            ])
        #expect(model.notices.map(\.kind) == [.status, .dialog])
    }

    @Test("a dialog and a status Notice with the same copy do not say the same thing")
    func dialogAndStatusWithSameCopyDoNotCollapse() {
        let dialog = Notice(error: .storage(.openLibrary))
        let status = Notice(storageFailed: .openLibrary)
        #expect(copy(of: dialog) == copy(of: status))
        #expect(!dialog.says(status))
        #expect(!status.says(dialog))
        #expect(dialog.says(Notice(error: .storage(.openLibrary))))
    }
}
