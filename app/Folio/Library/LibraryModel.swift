import FolioCore
import Foundation
import Observation

/// The Library screen's state. Sends each operation to the `Library` and keeps
/// `items` current by reloading when the Library announces a change.
///
/// Every failure, thrown or announced as an event, queues a `Notice` for the view
/// to show; none is only logged.
@Observable @MainActor final class LibraryModel {
    private(set) var items: [LibraryItem] = []
    /// Pages done and total for Imports In Progress, updated without a reload.
    private(set) var liveProgress: [ImportID: (done: Int, total: Int)] = [:]
    /// Failures not yet dismissed, oldest first.
    private(set) var notices: [Notice] = []
    /// True once `start()` has loaded the items for the first time; until then
    /// `reload()` does nothing.
    private(set) var isLoaded = false
    /// Events fully handled by `start()`; lets tests wait for an event that changes no state.
    private(set) var handledEventCount = 0

    private let library: Library
    private let booksDirectory: URL

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
        #if DEBUG
            queueDebugNotices()
        #endif
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
            items = try await library.items()
        } catch {
            AppLog.library.error(
                "Could not load the Library: \(String(describing: error), privacy: .public)")
            queue(Notice(storageFailed: .updateLibrary))
        }
    }

    /// Loads what it can after a failure that has already queued its Notice, without
    /// a second one. `context` names that failure in the log.
    private func reloadAfterNotice(_ context: String) async {
        do {
            items = try await library.items()
        } catch {
            // Log-only: the Notice just queued already tells the user; a successful
            // reload still refreshes the list.
            AppLog.library.error(
                "Could not load the Library after \(context, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }

    #if DEBUG
        /// Exists only for manual checks of Notice presentation. Launching with
        /// `FOLIO_DEBUG_NOTICES=2` queues two Notices, to check the second is presented
        /// after the first is dismissed. `FOLIO_DEBUG_NOTICES=picker` queues one Notice
        /// 2 s after launch, to check a Notice queued while the file picker is open
        /// appears once the picker closes.
        private func queueDebugNotices() {
            switch ProcessInfo.processInfo.environment["FOLIO_DEBUG_NOTICES"] {
            case "2":
                queue(Notice(storageFailed: .updateLibrary))
                queue(Notice(storageFailed: .deleteBook))
            case "picker":
                Task {
                    // Ignored: this Task is never cancelled; it only delays a test Notice.
                    try? await Task.sleep(for: .seconds(2))
                    queue(Notice(storageFailed: .updateLibrary))
                }
            default:
                break
            }
        }
    #endif

    /// The Notice the view shows now; the rest wait their turn.
    var presentedNotice: Notice? { notices.first }

    /// Removes the presented Notice if it is `id`, so the next one, if any, is
    /// presented. A stale or repeated dismissal does nothing, so a waiting Notice
    /// is never removed unseen.
    func dismissNotice(_ id: Notice.ID) {
        guard presentedNotice?.id == id else { return }
        let notice = notices.removeFirst()
        AppLog.library.info(
            "Dismissed Notice \(notice.title, privacy: .private); \(self.notices.count) waiting")
    }

    /// Queues the Notice for a file picker that failed before the user picked a Source.
    func filePickerFailed() {
        queue(.filePickerFailed())
    }

    func importSource(_ url: URL) async {
        await perform(.import) {
            _ = try await self.library.createImport(from: url)
        }
    }

    func cancelImport(_ id: ImportID) async {
        await perform(.cancelImport) {
            try await self.library.cancelImport(id: id)
        }
    }

    func retryImport(_ id: ImportID) async {
        await perform(.retryImport) {
            try await self.library.retryImport(id: id)
        }
    }

    func removeImport(_ id: ImportID) async {
        await perform(.removeImport) {
            try await self.library.removeImport(id: id)
        }
    }

    func rename(_ id: BookID, to title: String) async {
        await perform(.rename) {
            try await self.library.rename(bookID: id, to: title)
        }
    }

    /// Records the open but does not reload: the Library order refreshes the next
    /// time the screen appears, so the Book does not jump while the user taps it.
    func open(_ id: BookID) async {
        await perform(.open) {
            try await self.library.open(bookID: id)
        }
    }

    func removeBook(_ id: BookID) async {
        await perform(.deleteBook) {
            try await self.library.removeBook(id: id)
        }
    }

    func coverURL(for book: Book) -> URL {
        booksDirectory.appending(path: book.folderName).appending(path: book.coverFileName)
    }

    // MARK: - Private

    /// Runs the user's `operation`, queueing a Notice if it fails.
    private func perform(
        _ operation: LibraryOperation, _ body: () async throws -> Void
    ) async {
        do {
            try await body()
        } catch let error as LibraryError {
            AppLog.library.error(
                "Could not \(operation.rawValue, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            queue(Notice(error: error))
        } catch {
            // The Library throws only LibraryError, so this is a programming error.
            AppLog.library.fault(
                "Could not \(operation.rawValue, privacy: .public), unexpected error: \(String(describing: error), privacy: .public)"
            )
            queue(Notice(storageFailed: operation))
        }
    }

    /// Appends `notice` unless it repeats the last one queued, so the same
    /// failure reported twice in a row is shown once.
    private func queue(_ notice: Notice) {
        if let last = notices.last, last.says(notice) { return }
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
        case .bookOpened:
            break
        case .libraryStorageFailed(let operation):
            queue(Notice(storageFailed: operation))
            await reloadAfterNotice("a storage failure")
        }
        handledEventCount += 1
    }
}
