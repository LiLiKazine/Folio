import FolioCore
import Foundation
import SwiftData

/// Stored form of a `Book`. Lives only inside `SwiftDataBookRepository`; callers
/// see `Book` values.
@Model
final class BookModel {
    @Attribute(.unique) var id: UUID
    var title: String
    var folderName: String
    /// Page file names in the Book's reading order, exactly as given.
    var pageFileNames: [String]
    var coverFileName: String
    var importedAt: Date
    var lastOpenedAt: Date?
    var readingPosition: Int?
    /// `ReadingMode`'s raw value. Empty for a Book stored before Reading Modes existed;
    /// a value that names no case also reads as Page by Page.
    var readingMode: String?

    init(_ book: Book) {
        id = book.id.rawValue
        title = book.title
        folderName = book.folderName
        pageFileNames = book.pages.map(\.fileName)
        coverFileName = book.coverFileName
        importedAt = book.importedAt
        lastOpenedAt = book.lastOpenedAt
        readingPosition = book.readingPosition
        readingMode = book.readingMode.rawValue
    }

    /// Overwrites every stored field with `book`'s values; `id` is kept.
    func apply(_ book: Book) {
        title = book.title
        folderName = book.folderName
        pageFileNames = book.pages.map(\.fileName)
        coverFileName = book.coverFileName
        importedAt = book.importedAt
        lastOpenedAt = book.lastOpenedAt
        readingPosition = book.readingPosition
        readingMode = book.readingMode.rawValue
    }

    var book: Book {
        Book(
            id: BookID(id),
            title: title,
            folderName: folderName,
            pages: pageFileNames.map { Page(fileName: $0) },
            coverFileName: coverFileName,
            importedAt: importedAt,
            lastOpenedAt: lastOpenedAt,
            readingPosition: readingPosition,
            readingMode: readingMode.flatMap(ReadingMode.init(rawValue:)) ?? .pageByPage
        )
    }
}
