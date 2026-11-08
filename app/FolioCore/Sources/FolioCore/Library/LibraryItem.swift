import Foundation

/// One entry in the Library: a Book, or an Import that has not produced one.
public enum LibraryItem: Identifiable, Hashable, Sendable {
    case book(Book)
    case importRecord(Import)

    public var id: String {
        switch self {
        case .book(let book): "book:\(book.id.rawValue.uuidString)"
        case .importRecord(let record): "import:\(record.id.rawValue.uuidString)"
        }
    }
}

extension Array where Element == LibraryItem {
    /// In Progress first, then Queued by createdAt, then Failed by createdAt, then Books in Library order.
    public func inLibraryOrder() -> [LibraryItem] {
        var records: [Import] = []
        var books: [Book] = []
        for item in self {
            switch item {
            case .book(let book): books.append(book)
            case .importRecord(let record): records.append(record)
            }
        }
        func ordered(_ status: ImportStatus) -> [LibraryItem] {
            records.filter { $0.status == status }.sorted { $0.createdAt < $1.createdAt }
                .map(LibraryItem.importRecord)
        }
        return ordered(.inProgress) + ordered(.queued) + ordered(.failed)
            + books.inLibraryOrder().map(LibraryItem.book)
    }
}
