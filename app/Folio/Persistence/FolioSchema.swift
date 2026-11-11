import Foundation
import SwiftData

/// The first shipped shape of the Library store, frozen: never edit these models.
/// They exist so the store can be opened and migrated to the current shape. When a
/// model changes again, freeze copies of the then-current models inside a new enum
/// like this one, add a `FolioSchemaV4` with the new shapes, and add a stage to
/// `FolioMigrationPlan`. V3 added `LibraryOrderModel` and changed no existing model, so V2
/// and V3 both still name the live `BookModel` and `ImportModel`. When either model changes,
/// BOTH V2 and V3 must be given frozen copies: freezing only V3 would make
/// `v2StoreOpensWithNoLibraryOrder` write its store in the new shape and prove nothing.
enum FolioSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [BookModel.self, ImportModel.self] }

    @Model
    final class BookModel {
        @Attribute(.unique) var id: UUID
        var title: String
        var folderName: String
        var pageFileNames: [String]
        var coverFileName: String
        var importedAt: Date
        var lastOpenedAt: Date?
        var readingPosition: Int?

        init(
            id: UUID, title: String, folderName: String, pageFileNames: [String],
            coverFileName: String, importedAt: Date, lastOpenedAt: Date?, readingPosition: Int?
        ) {
            self.id = id
            self.title = title
            self.folderName = folderName
            self.pageFileNames = pageFileNames
            self.coverFileName = coverFileName
            self.importedAt = importedAt
            self.lastOpenedAt = lastOpenedAt
            self.readingPosition = readingPosition
        }
    }

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
        var bookID: UUID?
        var createdAt: Date
        var finishedAt: Date?

        init(
            id: UUID, status: String, sourceBookmark: Data, sourceName: String, title: String,
            pagesDone: Int, pagesTotal: Int?, failureReason: String?, bookID: UUID?,
            createdAt: Date, finishedAt: Date?
        ) {
            self.id = id
            self.status = status
            self.sourceBookmark = sourceBookmark
            self.sourceName = sourceName
            self.title = title
            self.pagesDone = pagesDone
            self.pagesTotal = pagesTotal
            self.failureReason = failureReason
            self.bookID = bookID
            self.createdAt = createdAt
            self.finishedAt = finishedAt
        }
    }
}

/// V1 plus `BookModel.readingMode`, an optional text field that is empty for every Book
/// stored before it existed.
enum FolioSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [BookModel.self, ImportModel.self] }
}

/// The current shape of the Library store: V2 plus `LibraryOrderModel`, the one row holding
/// the Library Order. A store written before it existed has no such row.
enum FolioSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [BookModel.self, ImportModel.self, LibraryOrderModel.self]
    }
}

/// Migrations between the Library store's schemas.
enum FolioMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [FolioSchemaV1.self, FolioSchemaV2.self, FolioSchemaV3.self]
    }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: FolioSchemaV1.self, toVersion: FolioSchemaV2.self),
            .lightweight(fromVersion: FolioSchemaV2.self, toVersion: FolioSchemaV3.self),
        ]
    }
}
