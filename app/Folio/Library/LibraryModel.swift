import FolioCore
import Foundation
import Observation

/// The Library screen's state. Sends each operation to the `Library` and keeps
/// `items` current by reloading when the Library announces a change.
///
/// Errors from the Library are logged with `AppLog.library` and never reach the view.
@Observable @MainActor final class LibraryModel {
    /// An Import that has just Failed, for the view to tell the user about.
    struct FailureAlert: Identifiable, Equatable {
        let id: ImportID
        let sourceName: String
        let reason: ImportFailureReason
    }

    private(set) var items: [LibraryItem] = []
    /// Pages done and total for Imports In Progress, updated without a reload.
    private(set) var liveProgress: [ImportID: (done: Int, total: Int)] = [:]
    var failureAlert: FailureAlert?
    var isLoaded = false
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
        } catch {
            AppLog.library.error(
                "Could not start the Library: \(String(describing: error), privacy: .public)")
        }
        await reload()
        isLoaded = true
        for await event in library.events {
            await handle(event)
        }
    }

    func reload() async {
        do {
            items = try await library.items()
        } catch {
            AppLog.library.error(
                "Could not load the Library: \(String(describing: error), privacy: .public)")
        }
    }

    func importSource(_ url: URL) async {
        do {
            _ = try await library.createImport(from: url)
        } catch {
            AppLog.library.error(
                "Could not create an Import: \(String(describing: error), privacy: .public)")
        }
    }

    func cancelImport(_ id: ImportID) async {
        await perform("cancel Import \(id.rawValue.uuidString)") {
            try await self.library.cancelImport(id: id)
        }
    }

    func retryImport(_ id: ImportID) async {
        await perform("retry Import \(id.rawValue.uuidString)") {
            try await self.library.retryImport(id: id)
        }
    }

    func removeImport(_ id: ImportID) async {
        await perform("remove Import \(id.rawValue.uuidString)") {
            try await self.library.removeImport(id: id)
        }
    }

    func rename(_ id: BookID, to title: String) async {
        await perform("rename Book \(id.rawValue.uuidString)") {
            try await self.library.rename(bookID: id, to: title)
        }
    }

    /// Records the open but does not reload: the Library order refreshes the next
    /// time the screen appears, so the Book does not jump while the user taps it.
    func open(_ id: BookID) async {
        await perform("open Book \(id.rawValue.uuidString)") {
            try await self.library.open(bookID: id)
        }
    }

    func removeBook(_ id: BookID) async {
        await perform("remove Book \(id.rawValue.uuidString)") {
            try await self.library.removeBook(id: id)
        }
    }

    func coverURL(for book: Book) -> URL {
        booksDirectory.appending(path: book.folderName).appending(path: book.coverFileName)
    }

    // MARK: - Private

    private func perform(
        _ operation: String, _ body: () async throws -> Void
    ) async {
        do {
            try await body()
        } catch {
            AppLog.library.error(
                "Could not \(operation, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
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
            await reload()
            failureAlert = FailureAlert(id: id, sourceName: sourceName, reason: reason)
        case .bookOpened:
            break
        }
        handledEventCount += 1
    }
}
