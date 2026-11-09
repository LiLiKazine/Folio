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
    /// A Book's Reading Position moved to a Page because the reader turned to it.
    case readingPositionChanged(BookID, page: Int)
    /// A Book's Reading Mode changed because the reader chose another.
    case readingModeChanged(BookID, mode: ReadingMode)
    case bookRemoved(BookID)
    /// A change the Library could not save or apply on the user's behalf, with no
    /// caller to throw to; names what it was trying to do.
    case libraryStorageFailed(LibraryOperation)
}
