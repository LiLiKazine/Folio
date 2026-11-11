import Foundation
import SwiftData

enum PersistenceError: Error, Equatable {
    /// A stored raw value no longer names a case of its enum.
    case corruptValue(field: String, value: String)
}

/// Where the Library lives on disk: the Books directory holding every Book's
/// Pages, and the SwiftData store beside them.
enum LibraryStorage {
    /// `<Application Support>/<bundle id>/Books`, created if needed and marked `isExcludedFromBackup = true`.
    static func booksDirectory() throws -> URL {
        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        var directory =
            applicationSupport
            .appending(
                path: Bundle.main.bundleIdentifier ?? AppLog.subsystem, directoryHint: .isDirectory
            )
            .appending(path: "Books", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        return directory
    }

    /// Container whose store file is `<booksDirectory>/Library.store`.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        if inMemory {
            let schema = Schema(versionedSchema: FolioSchemaV3.self)
            return try makeContainer(
                schema: schema,
                configuration: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        }
        let storeURL = try booksDirectory().appending(
            path: "Library.store", directoryHint: .notDirectory)
        AppLog.persistence.info("Library store at \(storeURL.path, privacy: .private)")
        return try makeContainer(at: storeURL)
    }

    /// Container for the store file at `url`, opened in the current schema with
    /// `FolioMigrationPlan`.
    static func makeContainer(at url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: FolioSchemaV3.self)
        return try makeContainer(
            schema: schema, configuration: ModelConfiguration(schema: schema, url: url))
    }

    private static func makeContainer(
        schema: Schema, configuration: ModelConfiguration
    ) throws -> ModelContainer {
        try ModelContainer(
            for: schema, migrationPlan: FolioMigrationPlan.self, configurations: [configuration])
    }
}
