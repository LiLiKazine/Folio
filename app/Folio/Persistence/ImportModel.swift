import FolioCore
import Foundation
import SwiftData

/// Stored form of an `Import`. Lives only inside `SwiftDataImportRepository`;
/// callers see `Import` values. `status` and `failureReason` hold the enums'
/// raw values.
@Model
final class ImportModel {
    @Attribute(.unique) var id: UUID
    var status: String
    var sourceBookmark: Data
    var sourceName: String
    var title: String
    var pagesDone: Int
    var pagesTotal: Int?
    var failureReason: String?
    /// May be set while the Import is still In Progress or Failed (it is
    /// pre-assigned); never read as a sign of status.
    var bookID: UUID?
    var createdAt: Date
    var finishedAt: Date?

    init(_ record: Import) {
        id = record.id.rawValue
        status = record.status.rawValue
        sourceBookmark = record.sourceBookmark
        sourceName = record.sourceName
        title = record.title
        pagesDone = record.pagesDone
        pagesTotal = record.pagesTotal
        failureReason = record.failureReason?.rawValue
        bookID = record.bookID?.rawValue
        createdAt = record.createdAt
        finishedAt = record.finishedAt
    }

    /// Overwrites every stored field with `record`'s values; `id` is kept.
    func apply(_ record: Import) {
        status = record.status.rawValue
        sourceBookmark = record.sourceBookmark
        sourceName = record.sourceName
        title = record.title
        pagesDone = record.pagesDone
        pagesTotal = record.pagesTotal
        failureReason = record.failureReason?.rawValue
        bookID = record.bookID?.rawValue
        createdAt = record.createdAt
        finishedAt = record.finishedAt
    }

    /// Throws `PersistenceError.corruptValue` if a stored raw value no longer
    /// names a case.
    var record: Import {
        get throws {
            guard let status = ImportStatus(rawValue: status) else {
                throw PersistenceError.corruptValue(field: "status", value: status)
            }
            var reason: ImportFailureReason?
            if let failureReason {
                guard let parsed = ImportFailureReason(rawValue: failureReason) else {
                    throw PersistenceError.corruptValue(
                        field: "failureReason", value: failureReason)
                }
                reason = parsed
            }
            return Import(
                id: ImportID(id),
                status: status,
                sourceBookmark: sourceBookmark,
                sourceName: sourceName,
                title: title,
                pagesDone: pagesDone,
                pagesTotal: pagesTotal,
                failureReason: reason,
                bookID: bookID.map { BookID($0) },
                createdAt: createdAt,
                finishedAt: finishedAt
            )
        }
    }
}
