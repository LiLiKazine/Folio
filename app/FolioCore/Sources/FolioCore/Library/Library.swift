import Foundation

public enum LibraryError: Error, Equatable { case emptyTitle, notFound, invalidStatus }

/// Owns the Books and Imports, runs Imports one at a time in creation order, and
/// announces each change as a `LibraryEvent`.
public actor Library {
    public nonisolated let events: AsyncStream<LibraryEvent>

    private let continuation: AsyncStream<LibraryEvent>.Continuation
    private let books: any BookRepository
    private let imports: any ImportRepository
    private let pipeline: ImportPipeline
    private let sourceAccess: any SourceAccess
    private let now: @Sendable () -> Date
    private let booksDirectory: URL
    /// FileManager is not `Sendable`, but its methods are thread-safe when no delegate is set.
    nonisolated(unsafe) private let fileManager = FileManager.default

    /// Runs Queued Imports one after another; nil when idle.
    private var scheduler: Task<Void, Never>?
    /// Set when the queue may have grown while the scheduler was looking at it.
    private var queueChanged = false
    /// The Import the scheduler has taken, kept current with its progress.
    private var running: Import?

    public init(
        books: any BookRepository, imports: any ImportRepository,
        pipeline: ImportPipeline, sourceAccess: any SourceAccess,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        (events, continuation) = AsyncStream.makeStream(
            of: LibraryEvent.self, bufferingPolicy: .unbounded)
        self.books = books
        self.imports = imports
        self.pipeline = pipeline
        self.sourceAccess = sourceAccess
        self.now = now
        self.booksDirectory = pipeline.booksDirectory
    }

    /// Deletes staging, returns In Progress Imports to Queued, removes Book records without folders and folders without records, then starts the scheduler.
    public func start() async throws {
        try fileManager.createDirectory(
            at: pipeline.stagingRoot, withIntermediateDirectories: true)
        try pipeline.removeAllStaging()
        for var record in try await imports.imports(status: .inProgress) {
            record.status = .queued
            record.pagesDone = 0
            record.pagesTotal = nil
            try await imports.update(record)
        }
        try await reconcileBookFolders()
        kick()
    }

    public func items() async throws -> [LibraryItem] {
        var items = try await books.allBooks().map(LibraryItem.book)
        for status in [ImportStatus.inProgress, .queued, .failed] {
            items += try await imports.imports(status: status).map(LibraryItem.importRecord)
        }
        return items.inLibraryOrder()
    }

    public func createImport(from pickedURL: URL) async throws -> ImportID {
        let record = Import(
            id: ImportID(), status: .queued,
            sourceBookmark: try sourceAccess.bookmark(for: pickedURL),
            sourceName: pickedURL.lastPathComponent,
            title: SourceScanner.title(forSource: pickedURL), pagesDone: 0, pagesTotal: nil,
            failureReason: nil, bookID: nil, createdAt: now(), finishedAt: nil)
        try await imports.add(record)
        continuation.yield(.importQueued(record.id, title: record.title))
        kick()
        return record.id
    }

    public func cancelImport(id: ImportID) async throws {
        let record = try await importRecord(id: id)
        if running?.id == id {
            scheduler?.cancel()
        } else if record.status == .queued {
            try await fail(record, reason: .cancelled)
        } else {
            throw LibraryError.invalidStatus
        }
    }

    public func retryImport(id: ImportID) async throws {
        var record = try await importRecord(id: id)
        guard record.status == .failed else { throw LibraryError.invalidStatus }
        record.status = .queued
        record.pagesDone = 0
        record.pagesTotal = nil
        record.failureReason = nil
        record.finishedAt = nil
        try await imports.update(record)
        continuation.yield(.importQueued(record.id, title: record.title))
        kick()
    }

    public func removeImport(id: ImportID) async throws {
        guard try await importRecord(id: id).status == .failed else {
            throw LibraryError.invalidStatus
        }
        try await imports.remove(id: id)
        continuation.yield(.importRemoved(id))
    }

    public func rename(bookID: BookID, to title: String) async throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw LibraryError.emptyTitle }
        var book = try await book(id: bookID)
        book.title = title
        try await books.update(book)
        continuation.yield(.bookRenamed(bookID, title: title))
    }

    public func open(bookID: BookID) async throws {
        var book = try await book(id: bookID)
        let openedAt = now()
        book.lastOpenedAt = openedAt
        try await books.update(book)
        continuation.yield(.bookOpened(bookID, at: openedAt))
    }

    public func removeBook(id: BookID) async throws {
        let book = try await book(id: id)
        let folder = booksDirectory.appending(path: book.folderName)
        if fileManager.fileExists(atPath: folder.path) {
            try fileManager.removeItem(at: folder)
        }
        try await books.remove(id: id)
        continuation.yield(.bookRemoved(id))
    }

    // MARK: - Lookup

    private func importRecord(id: ImportID) async throws -> Import {
        guard let record = try await imports.importRecord(id: id) else {
            throw LibraryError.notFound
        }
        return record
    }

    private func book(id: BookID) async throws -> Book {
        guard let book = try await books.book(id: id) else { throw LibraryError.notFound }
        return book
    }

    // MARK: - Launch reconciliation

    /// Only folders named by a UUID are Book folders; anything else is left alone.
    private func reconcileBookFolders() async throws {
        let folders = Set(
            try fileManager.contentsOfDirectory(atPath: booksDirectory.path).filter {
                UUID(uuidString: $0) != nil
            })
        var recorded: Set<String> = []
        for book in try await books.allBooks() {
            if folders.contains(book.folderName) {
                recorded.insert(book.folderName)
            } else {
                try await books.remove(id: book.id)
            }
        }
        for orphan in folders.subtracting(recorded) {
            try fileManager.removeItem(at: booksDirectory.appending(path: orphan))
        }
    }

    // MARK: - Scheduler

    private func kick() {
        queueChanged = true
        guard scheduler == nil else { return }
        scheduler = Task { await self.runQueue() }
    }

    /// Runs the oldest Queued Import until none remain. A cancelled Import ends this
    /// task, so a fresh one is kicked for whatever is still Queued.
    private func runQueue() async {
        while !Task.isCancelled {
            queueChanged = false
            guard let next = try? await imports.imports(status: .queued).first else {
                if queueChanged { continue }
                break
            }
            await run(next)
        }
        scheduler = nil
        if Task.isCancelled { kick() }
    }

    private func run(_ queued: Import) async {
        var record = queued
        record.status = .inProgress
        running = record
        defer { running = nil }
        do {
            try Task.checkCancellation()
            try await imports.update(record)
            let bookID = BookID()
            let book = try await sourceAccess.withAccess(to: record.sourceBookmark) {
                [pipeline, now, title = record.title] source in
                try await pipeline.run(
                    source: source, bookID: bookID, title: title, importedAt: now()
                ) { done, total in
                    await self.recordProgress(done: done, total: total)
                }
            }
            try await books.add(book)
            record = running ?? record
            record.status = .completed
            record.bookID = book.id
            record.finishedAt = now()
            try await imports.update(record)
            continuation.yield(.importCompleted(record.id, book))
        } catch {
            try? await fail(running ?? record, reason: Self.failureReason(for: error))
        }
    }

    private func recordProgress(done: Int, total: Int) async {
        guard var record = running else { return }
        let isFirst = record.pagesTotal == nil
        record.pagesDone = done
        record.pagesTotal = total
        running = record
        try? await imports.update(record)
        continuation.yield(
            isFirst
                ? .importStarted(record.id, pagesTotal: total)
                : .importProgressed(record.id, pagesDone: done, pagesTotal: total))
    }

    private func fail(_ record: Import, reason: ImportFailureReason) async throws {
        var record = record
        record.status = .failed
        record.failureReason = reason
        record.finishedAt = now()
        try await imports.update(record)
        continuation.yield(
            .importFailed(record.id, sourceName: record.sourceName, reason: reason))
    }

    private static func failureReason(for error: any Error) -> ImportFailureReason {
        switch error {
        case let failure as ImportFailure: failure.reason
        case SourceAccessError.unavailable: .sourceUnavailable
        case SourceAccessError.notDownloaded: .sourceNotDownloaded
        case is CancellationError: .cancelled
        default: .storageFailure
        }
    }
}
