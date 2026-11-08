/// What the user was trying to do, in glossary terms, when a Library operation
/// failed. The raw value is how a Notice names it.
public enum LibraryOperation: String, Sendable, Equatable, CaseIterable {
    case `import` = "Import"
    case cancelImport = "Cancel Import"
    case retryImport = "Retry Import"
    case removeImport = "Remove Import"
    case rename = "Rename"
    case open = "Open"
    case deleteBook = "Delete Book"
    case updateLibrary = "Update the Library"
    case openLibrary = "Open the Library"
}

/// The only error the Library's public operations throw. Every case names the
/// operation that failed, so it can be shown to the user as a Notice.
public enum LibraryError: Error, Equatable, Sendable {
    /// A rename to a Title that is empty once whitespace is trimmed.
    case emptyTitle
    /// The Book or Import is no longer in the Library.
    case notFound(LibraryOperation)
    /// The Import's status does not allow the operation, for example Retry on an
    /// Import that is not Failed.
    case invalidStatus(LibraryOperation)
    /// The picked Source could not be referenced or opened.
    case sourceUnavailable(sourceName: String)
    /// The Source is not downloaded to this device. Reserved for operations that open
    /// the Source; an Import that hits it while running ends Failed instead.
    case sourceNotDownloaded(sourceName: String)
    /// A repository or file-system change could not be saved.
    case storage(LibraryOperation)

    public var operation: LibraryOperation {
        switch self {
        case .emptyTitle: .rename
        case .notFound(let operation), .invalidStatus(let operation), .storage(let operation):
            operation
        case .sourceUnavailable, .sourceNotDownloaded: .import
        }
    }
}
