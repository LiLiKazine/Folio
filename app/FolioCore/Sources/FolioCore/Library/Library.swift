import Foundation

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
    /// Imports cancelled while Queued. A queue fetch that was in flight during the
    /// cancel can still hand one to the scheduler, which must skip it. Cleared on retry.
    private var cancelledWhileQueued: Set<ImportID> = []
    /// Imports whose Failed status could not be saved. Storage may still show one as
    /// Queued, so the scheduler skips it for the rest of this session rather than
    /// running it again at once and failing the same way. Cleared on retry.
    private var unsavedFailures: Set<ImportID> = []

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

    /// Deletes leftover staging, removes Book records without folders and folders without records,
    /// returns In Progress Imports to Queued (or Completed when their Book was already
    /// added), then starts the scheduler. A step that fails is skipped, so recovery and
    /// the scheduler always run; one the user would notice also emits
    /// `libraryStorageFailed`. Throws only `LibraryError` — `.storage(.openLibrary)` when
    /// the In Progress Imports cannot be read, after starting the scheduler anyway.
    public func start() async throws(LibraryError) {
        defer { kick() }
        removeLeftoverStaging()
        await reconcileBookFolders()
        let inProgress = try await storageGuard(.openLibrary) {
            try await imports.imports(status: .inProgress)
        }
        for var record in inProgress {
            do {
                if let book = try await addedBook(for: record) {
                    try await complete(record, with: book)
                    continue
                }
                record.status = .queued
                record.pagesDone = 0
                record.pagesTotal = nil
                try await imports.update(record)
            } catch {
                Self.logCleanupFailure(
                    "recover Import \(record.id.rawValue.uuidString)", error: error)
                continuation.yield(.libraryStorageFailed(.openLibrary))
            }
        }
    }

    /// The Books and unfinished Imports in Library order. Throws only `LibraryError`.
    public func items() async throws(LibraryError) -> [LibraryItem] {
        try await storageGuard(.updateLibrary) {
            var items = try await books.allBooks().map(LibraryItem.book)
            for status in [ImportStatus.inProgress, .queued, .failed] {
                items += try await imports.imports(status: status).map(LibraryItem.importRecord)
            }
            return items.inLibraryOrder()
        }
    }

    /// Queues a new Import of the picked Source. Throws only `LibraryError`:
    /// `.sourceUnavailable` or `.sourceNotDownloaded` when the Source cannot be
    /// referenced, `.storage(.import)` when the Import cannot be saved.
    public func createImport(from pickedURL: URL) async throws(LibraryError) -> ImportID {
        let sourceName = pickedURL.lastPathComponent
        let bookmark: Data
        do {
            bookmark = try sourceAccess.bookmark(for: pickedURL)
        } catch {
            switch error {
            case .unavailable: throw .sourceUnavailable(sourceName: sourceName)
            case .notDownloaded: throw .sourceNotDownloaded(sourceName: sourceName)
            }
        }
        let record = Import(
            id: ImportID(), status: .queued, sourceBookmark: bookmark, sourceName: sourceName,
            title: SourceScanner.title(forSource: pickedURL), pagesDone: 0, pagesTotal: nil,
            failureReason: nil, bookID: nil, createdAt: now(), finishedAt: nil)
        try await storageGuard(.import) { try await imports.add(record) }
        continuation.yield(.importQueued(record.id, title: record.title))
        kick()
        return record.id
    }

    /// Cancels a running or Queued Import. Throws only `LibraryError`, naming
    /// `.cancelImport`.
    public func cancelImport(id: ImportID) async throws(LibraryError) {
        try await storageGuard(.cancelImport) {
            let record = try await importRecord(id: id, for: .cancelImport)
            if running?.id == id {
                scheduler?.cancel()
            } else if record.status == .queued {
                cancelledWhileQueued.insert(id)
                do {
                    try await fail(record, reason: .cancelled)
                } catch {
                    cancelledWhileQueued.remove(id)
                    throw error
                }
            } else {
                throw LibraryError.invalidStatus(.cancelImport)
            }
        }
    }

    /// Queues a Failed Import again. Throws only `LibraryError`, naming `.retryImport`.
    public func retryImport(id: ImportID) async throws(LibraryError) {
        try await storageGuard(.retryImport) {
            var record = try await importRecord(id: id, for: .retryImport)
            guard record.status == .failed else {
                throw LibraryError.invalidStatus(.retryImport)
            }
            if let book = try await addedBook(for: record) {
                try await complete(record, with: book)
                return
            }
            cancelledWhileQueued.remove(id)
            unsavedFailures.remove(id)
            record.status = .queued
            record.pagesDone = 0
            record.pagesTotal = nil
            record.failureReason = nil
            record.finishedAt = nil
            try await imports.update(record)
            continuation.yield(.importQueued(record.id, title: record.title))
            kick()
        }
    }

    /// Takes a Failed Import out of the Library. Throws only `LibraryError`, naming
    /// `.removeImport`.
    public func removeImport(id: ImportID) async throws(LibraryError) {
        try await storageGuard(.removeImport) {
            guard try await importRecord(id: id, for: .removeImport).status == .failed else {
                throw LibraryError.invalidStatus(.removeImport)
            }
            try await imports.remove(id: id)
            continuation.yield(.importRemoved(id))
        }
    }

    /// Changes a Book's Title. Throws only `LibraryError`: `.emptyTitle`, or a case
    /// naming `.rename`.
    public func rename(bookID: BookID, to title: String) async throws(LibraryError) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw .emptyTitle }
        try await storageGuard(.rename) {
            var book = try await book(id: bookID, for: .rename)
            book.title = title
            try await books.update(book)
            continuation.yield(.bookRenamed(bookID, title: title))
        }
    }

    /// Records that a Book was opened. Throws only `LibraryError`, naming `.open`.
    public func open(bookID: BookID) async throws(LibraryError) {
        try await storageGuard(.open) {
            var book = try await book(id: bookID, for: .open)
            let openedAt = now()
            book.lastOpenedAt = openedAt
            try await books.update(book)
            continuation.yield(.bookOpened(bookID, at: openedAt))
        }
    }

    /// Removes the record first, so a Book is never listed without its folder. A folder
    /// that cannot be deleted is left as an orphan for launch reconciliation and emits
    /// `libraryStorageFailed(.deleteBook)` after `bookRemoved`.
    /// Throws only `LibraryError`, naming `.deleteBook`.
    public func removeBook(id: BookID) async throws(LibraryError) {
        let book = try await storageGuard(.deleteBook) {
            let book = try await book(id: id, for: .deleteBook)
            try await books.remove(id: id)
            return book
        }
        continuation.yield(.bookRemoved(id))
        let folder = booksDirectory.appending(path: book.folderName)
        guard fileManager.fileExists(atPath: folder.path) else { return }
        do {
            try fileManager.removeItem(at: folder)
        } catch {
            LibraryLog.logger.error(
                "Could not delete the folder of removed Book \(id.rawValue.uuidString, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            continuation.yield(.libraryStorageFailed(.deleteBook))
        }
    }

    // MARK: - Errors

    /// Runs `body` for the public operation `operation`, so that operation throws only
    /// `LibraryError`: a `LibraryError` passes through unchanged, and anything else is
    /// logged and becomes `.storage(operation)`.
    private func storageGuard<T>(
        _ operation: LibraryOperation, _ body: () async throws -> T
    ) async throws(LibraryError) -> T {
        do {
            return try await body()
        } catch let error as LibraryError {
            throw error
        } catch {
            LibraryLog.logger.error(
                "Could not \(operation.rawValue, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            throw .storage(operation)
        }
    }

    // MARK: - Lookup

    private func importRecord(id: ImportID, for operation: LibraryOperation) async throws -> Import
    {
        guard let record = try await imports.importRecord(id: id) else {
            throw LibraryError.notFound(operation)
        }
        return record
    }

    private func book(id: BookID, for operation: LibraryOperation) async throws -> Book {
        guard let book = try await books.book(id: id) else {
            throw LibraryError.notFound(operation)
        }
        return book
    }

    /// The Book an earlier run of `record` already added, if it got that far before
    /// the Import could be marked Completed.
    private func addedBook(for record: Import) async throws -> Book? {
        guard let bookID = record.bookID else { return nil }
        return try await books.book(id: bookID)
    }

    // MARK: - Launch reconciliation

    /// Creates the Books directory if needed, then deletes staging a killed run left in
    /// the system temporary directory.
    private func removeLeftoverStaging() {
        do {
            try fileManager.createDirectory(at: booksDirectory, withIntermediateDirectories: true)
        } catch {
            // Log-only: an Import that needs the directory ends Failed with its own reason.
            Self.logCleanupFailure("create the Books directory", error: error)
        }
        do {
            try pipeline.removeLeftoverStaging()
        } catch {
            // Log-only: leftover staging is temporary files that nothing in the Library lists.
            Self.logCleanupFailure("remove leftover staging", error: error)
        }
    }

    /// Only folders named by a UUID are Book folders; anything else is left alone.
    /// Each record and folder is handled on its own, so one failure skips only itself.
    /// A Book record that may be left without its folder emits
    /// `libraryStorageFailed(.updateLibrary)`, since the user would see a Book that
    /// cannot be read.
    private func reconcileBookFolders() async {
        let folders: Set<String>
        let allBooks: [Book]
        do {
            folders = Set(
                try fileManager.contentsOfDirectory(atPath: booksDirectory.path).filter {
                    UUID(uuidString: $0) != nil
                })
            allBooks = try await books.allBooks()
        } catch {
            Self.logCleanupFailure("reconcile Book folders", error: error)
            continuation.yield(.libraryStorageFailed(.updateLibrary))
            return
        }
        var recorded: Set<String> = []
        for book in allBooks {
            if folders.contains(book.folderName) {
                recorded.insert(book.folderName)
                continue
            }
            do {
                try await books.remove(id: book.id)
            } catch {
                Self.logCleanupFailure(
                    "remove Book \(book.id.rawValue.uuidString) without folder", error: error)
                continuation.yield(.libraryStorageFailed(.updateLibrary))
            }
        }
        for orphan in folders.subtracting(recorded) {
            do {
                try fileManager.removeItem(at: booksDirectory.appending(path: orphan))
            } catch {
                // Log-only: a folder without a record is not listed, so it only takes up space.
                Self.logCleanupFailure("remove orphan folder \(orphan)", error: error)
            }
        }
    }

    private static func logCleanupFailure(_ step: String, error: any Error) {
        LibraryLog.logger.error(
            "Launch cleanup could not \(step, privacy: .public): \(String(describing: error), privacy: .public)"
        )
    }

    // MARK: - Scheduler

    private func kick() {
        queueChanged = true
        guard scheduler == nil else { return }
        scheduler = Task { await self.runQueue() }
    }

    /// Runs the oldest Queued Import until none remain. A cancelled Import ends this
    /// task, so a fresh one is kicked for whatever is still Queued. A queue that cannot be
    /// read emits `libraryStorageFailed(.updateLibrary)` and waits for the next change.
    private func runQueue() async {
        while !Task.isCancelled {
            queueChanged = false
            let queued: [Import]
            do {
                queued = try await imports.imports(status: .queued)
            } catch {
                LibraryLog.logger.error(
                    "Could not read Queued Imports: \(String(describing: error), privacy: .public)")
                continuation.yield(.libraryStorageFailed(.updateLibrary))
                break
            }
            guard
                let next = queued.first(where: {
                    !cancelledWhileQueued.contains($0.id) && !unsavedFailures.contains($0.id)
                })
            else {
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
        // A fresh id each run: a folder left by an earlier run under the old id
        // would block the pipeline's final move.
        let bookID = BookID()
        record.bookID = bookID
        running = record
        defer { running = nil }
        do {
            try Task.checkCancellation()
            try await imports.update(record)
            let book = try await sourceAccess.withAccess(to: record.sourceBookmark) {
                [pipeline, now, title = record.title] source in
                try await pipeline.run(
                    source: source, bookID: bookID, title: title, importedAt: now()
                ) { done, total in
                    await self.recordProgress(done: done, total: total)
                }
            }
            try await books.add(book)
            try await complete(running ?? record, with: book)
        } catch {
            await recordFailure(running ?? record, reason: Self.failureReason(for: error))
        }
    }

    private func complete(_ record: Import, with book: Book) async throws {
        var record = record
        record.status = .completed
        record.bookID = book.id
        record.finishedAt = now()
        try await imports.update(record)
        continuation.yield(.importCompleted(record.id, book))
    }

    /// Marks the running Import Failed, retrying the write once. If both writes fail,
    /// emits `libraryStorageFailed(.import)` and skips the Import for the rest of this
    /// session; storage keeps it In Progress or Queued, and it runs again after the next
    /// launch.
    private func recordFailure(_ record: Import, reason: ImportFailureReason) async {
        do {
            try await fail(record, reason: reason)
        } catch {
            do {
                try await fail(record, reason: reason)
            } catch {
                LibraryLog.logger.error(
                    "Could not record Import \(record.id.rawValue.uuidString, privacy: .public) as Failed: \(String(describing: error), privacy: .public)"
                )
                unsavedFailures.insert(record.id)
                continuation.yield(.libraryStorageFailed(.import))
            }
        }
    }

    private func recordProgress(done: Int, total: Int) async {
        guard var record = running else { return }
        let isFirst = record.pagesTotal == nil
        record.pagesDone = done
        record.pagesTotal = total
        running = record
        // Ignored: progress is shown from the events below, and launch recovery resets the
        // stored count, so a lost progress write changes nothing the user sees.
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
        case _ where ImportPipeline.isReadFailure(error): .sourceUnavailable
        default: .storageFailure
        }
    }
}
