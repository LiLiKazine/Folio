import FolioCore
import Foundation
import Observation

/// The Library screen's state. Sends each operation to the `Library` and keeps
/// `items` current by reloading when the Library announces a change.
///
/// Every failure, thrown or announced as an event, queues a `Notice` for the view
/// to show, except two the owner ruled log-only while reading (reading design,
/// "What the owner decided"): a failed Reading Position save (`turnPage`) and a
/// failed record of an open (`open`, unless the Book is gone).
@Observable @MainActor final class LibraryModel {
    private(set) var items: [LibraryItem] = []
    /// The Library Order the items follow; Recent, Descending until the Library has been read.
    private(set) var libraryOrder: LibraryOrder = .initial
    /// Pages done and total for Imports In Progress, updated without a reload.
    private(set) var liveProgress: [ImportID: (done: Int, total: Int)] = [:]
    /// Failures not yet dismissed, oldest first.
    private(set) var notices: [Notice] = []
    /// True once `start()` has loaded the items for the first time; until then
    /// `reload()` does nothing.
    private(set) var isLoaded = false

    private let library: Library
    private let booksDirectory: URL
    /// The latest Page asked for, per Book, not yet saved.
    private var pendingTurns: [BookID: Int] = [:]
    /// Books with a Reading Position save in progress.
    private var booksBeingSaved: Set<BookID> = []

    /// `booksDirectory` must be the directory the Library's `ImportPipeline` writes
    /// Book folders into (in the app, `LibraryStorage.booksDirectory()`); the model
    /// needs it to locate Covers, and the pipeline does not expose it outside FolioCore.
    init(library: Library, booksDirectory: URL) {
        self.library = library
        self.booksDirectory = booksDirectory
    }

    /// Starts the Library, loads the items, then handles the Library's events until
    /// the calling task is cancelled. The only consumer of `library.events`.
    func start() async {
        do {
            try await library.start()
            await loadItems()
        } catch {
            AppLog.library.error(
                "Could not start the Library: \(String(describing: error), privacy: .public)")
            queue(Notice(storageFailed: .openLibrary))
            await reloadAfterNotice("it failed to start")
        }
        isLoaded = true
        for await event in library.events {
            await handle(event)
        }
    }

    /// Reloads the items once `start()` has loaded them; before that it does nothing,
    /// so a reload when the screen appears cannot race the Library's launch step.
    func reload() async {
        guard isLoaded else { return }
        await loadItems()
    }

    /// Loads the items. A failure has no action of the user's behind it, so it queues
    /// the Update the Library Notice that says what they see may be out of date.
    private func loadItems() async {
        do {
            libraryOrder = try await library.libraryOrder()
            items = try await library.items()
        } catch {
            AppLog.library.error(
                "Could not load the Library: \(String(describing: error), privacy: .public)")
            queue(Notice(storageFailed: .updateLibrary))
        }
    }

    /// Loads what it can after a failure that has already queued its Notice, without
    /// a second one: the Library Order and the items, as `loadItems()` does, so the Sort
    /// menu's ticks and the grid agree. `context` names that failure in the log.
    private func reloadAfterNotice(_ context: String) async {
        do {
            libraryOrder = try await library.libraryOrder()
            items = try await library.items()
        } catch {
            // Log-only: the Notice just queued already tells the user; a successful
            // reload still refreshes the list.
            AppLog.library.error(
                "Could not load the Library after \(context, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// The dialog Notice the view shows now; later dialog Notices wait their turn.
    var presentedNotice: Notice? { notices.first { $0.kind == .dialog } }

    /// The status Notice the view shows now; later status Notices wait their turn.
    var statusNotice: Notice? { notices.first { $0.kind == .status } }

    /// Removes the Notice `id` if it is the one shown of its kind (`presentedNotice`
    /// or `statusNotice`), so the next of that kind, if any, is shown. A stale or
    /// repeated dismissal does nothing, so a waiting Notice is never removed unseen.
    func dismissNotice(_ id: Notice.ID) {
        guard presentedNotice?.id == id || statusNotice?.id == id,
            let index = notices.firstIndex(where: { $0.id == id })
        else { return }
        let notice = notices.remove(at: index)
        AppLog.library.info(
            "Dismissed Notice \(notice.title, privacy: .private); \(self.notices.count) waiting")
    }

    /// Queues the Notice for a file picker that failed before the user picked a Source.
    func filePickerFailed() {
        queue(.filePickerFailed())
    }

    func importSource(_ url: URL) async {
        await perform(.import) { () async throws(LibraryError) in
            _ = try await self.library.createImport(from: url)
        }
    }

    func cancelImport(_ id: ImportID) async {
        await perform(.cancelImport) { () async throws(LibraryError) in
            try await self.library.cancelImport(id: id)
        }
    }

    func retryImport(_ id: ImportID) async {
        await perform(.retryImport) { () async throws(LibraryError) in
            try await self.library.retryImport(id: id)
        }
    }

    func removeImport(_ id: ImportID) async {
        await perform(.removeImport) { () async throws(LibraryError) in
            try await self.library.removeImport(id: id)
        }
    }

    func rename(_ id: BookID, to title: String) async {
        await perform(.rename) { () async throws(LibraryError) in
            try await self.library.rename(bookID: id, to: title)
        }
    }

    /// Records the open but does not reload: under the Recent Sort the Book moves the next
    /// time the screen appears, so it does not jump while the user taps it.
    ///
    /// Returns the Book to show: the Library's current copy, so a Reading Position moved
    /// since `book` was read (by another window) is not lost. When the open could not be
    /// recorded it is logged and `book` itself is returned. Returns nil only when the
    /// Library no longer has the Book, which queues its Notice.
    @discardableResult
    func open(_ book: Book) async -> Book? {
        do {
            return try await library.open(bookID: book.id)
        } catch .notFound {
            AppLog.library.error("Could not open a Book the Library no longer has")
            queue(Notice(error: .notFound(.open)))
            return nil
        } catch {
            // Log-only by the owner's ruling (reading design, "Opening"): the Pages are
            // there and readable; a failed record changes only the Recent Sort.
            AppLog.library.error(
                "Could not record an open: \(String(describing: error), privacy: .public)")
            return book
        }
    }

    /// Moves the Book's Reading Position to the Page at `index`. Never queues a Notice.
    ///
    /// Saves one at a time per Book and always saves the latest Page asked for, so a
    /// burst of turns (a slider drag) ends with the last Page stored however long an
    /// earlier save takes. A call made while a save is running returns at once; the
    /// running call saves its Page.
    func turnPage(_ id: BookID, to index: Int) async {
        pendingTurns[id] = index
        guard booksBeingSaved.insert(id).inserted else { return }
        defer { booksBeingSaved.remove(id) }
        while let page = pendingTurns.removeValue(forKey: id) {
            do {
                try await library.turnPage(bookID: id, to: page)
            } catch {
                // Log-only by the owner's ruling (reading design, "A failed save while
                // reading is suppressed"): the Page turn itself visibly succeeded.
                AppLog.library.error(
                    "Could not save the Reading Position: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    /// Changes the Book's Reading Mode. Never queues a Notice.
    func chooseReadingMode(_ id: BookID, _ mode: ReadingMode) async {
        do {
            try await library.chooseReadingMode(bookID: id, mode)
        } catch {
            // Log-only by the owner's ruling (Reading Mode design, "A failed Reading Mode save is log-only"): the switch itself visibly succeeded.
            AppLog.library.error(
                "Could not save the Reading Mode: \(String(describing: error), privacy: .public)")
        }
    }

    /// Chooses the Library Order. A failed save queues a Notice and leaves `libraryOrder`
    /// and `items` as they were; the change shows through `libraryOrderChanged`.
    func chooseLibraryOrder(_ order: LibraryOrder) async {
        await perform(.chooseLibraryOrder) { () async throws(LibraryError) in
            try await self.library.chooseLibraryOrder(order)
        }
    }

    func removeBook(_ id: BookID) async {
        await perform(.deleteBook) { () async throws(LibraryError) in
            try await self.library.removeBook(id: id)
        }
    }

    /// Removes each Book, queueing a Notice for each that cannot be removed.
    func removeBooks(_ ids: Set<BookID>) async {
        for id in ids { await removeBook(id) }
    }

    func coverURL(for book: Book) -> URL {
        booksDirectory.appending(path: book.folderName).appending(path: book.coverFileName)
    }

    /// The file holding the Page at `index` of `book`: `<folder>/pages/<file name>`.
    func pageURL(for book: Book, at index: Int) -> URL {
        booksDirectory.appending(path: book.folderName)
            .appending(path: ImportPipeline.pagesName, directoryHint: .isDirectory)
            .appending(path: book.pages[index].fileName)
    }

    // MARK: - Private

    /// Runs the user's `operation`, queueing a Notice if it fails.
    private func perform(
        _ operation: LibraryOperation, _ body: () async throws(LibraryError) -> Void
    ) async {
        do {
            try await body()
        } catch {
            AppLog.library.error(
                "Could not \(operation.rawValue, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            queue(Notice(error: error))
        }
    }

    /// Appends `notice` unless it repeats the last one queued of its kind, so the
    /// same failure reported twice in a row is shown once even if a Notice of the
    /// other kind came between.
    private func queue(_ notice: Notice) {
        if let last = notices.last(where: { $0.kind == notice.kind }), last.says(notice) {
            return
        }
        notices.append(notice)
    }

    private func handle(_ event: LibraryEvent) async {
        switch event {
        case .importProgressed(let id, let done, let total):
            liveProgress[id] = (done: done, total: total)
        case .importQueued, .importStarted, .bookRenamed, .bookRemoved:
            await reload()
        case .importCompleted(let id, _), .importRemoved(let id):
            liveProgress[id] = nil
            await reload()
        case .importFailed(let id, let sourceName, let reason):
            liveProgress[id] = nil
            // A cancellation the user asked for needs no Notice; the Failed card remains.
            if reason == .cancelled {
                await reload()
            } else {
                // The Import's own Notice first, so a failing reload cannot precede it.
                queue(Notice(importFailed: sourceName, reason: reason))
                await reloadAfterNotice("an Import failed")
            }
        case .libraryOrderChanged(let order):
            libraryOrder = order
            await reload()
        case .bookOpened, .readingPositionChanged, .readingModeChanged:
            break
        case .libraryStorageFailed(let operation):
            queue(Notice(storageFailed: operation))
            await reloadAfterNotice("a storage failure")
        }
    }
}
