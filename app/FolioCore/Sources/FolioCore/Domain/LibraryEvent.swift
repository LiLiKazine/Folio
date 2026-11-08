import Foundation

public enum LibraryEvent: Sendable, Equatable {
    case importQueued(ImportID, title: String)
    case importStarted(ImportID, pagesTotal: Int)
    case importProgressed(ImportID, pagesDone: Int, pagesTotal: Int)
    case importCompleted(ImportID, Book)
    case importFailed(ImportID, sourceName: String, reason: ImportFailureReason)
    case importRemoved(ImportID)
    case bookRenamed(BookID, title: String)
    case bookOpened(BookID, at: Date)
    case bookRemoved(BookID)
}
