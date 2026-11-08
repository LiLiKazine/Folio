import FolioCore
import Foundation
import SwiftData

/// `ImportRepository` backed by SwiftData. `ImportModel`s never leave the actor.
@ModelActor
actor SwiftDataImportRepository: ImportRepository {
    func imports(status: ImportStatus) async throws -> [Import] {
        let rawStatus = status.rawValue
        let descriptor = FetchDescriptor<ImportModel>(
            predicate: #Predicate { $0.status == rawStatus },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor).map { try $0.record }
    }

    func importRecord(id: ImportID) async throws -> Import? {
        try model(id: id)?.record
    }

    func add(_ record: Import) async throws {
        modelContext.insert(ImportModel(record))
        try modelContext.save()
    }

    /// Inserts the Import if it is not stored yet.
    func update(_ record: Import) async throws {
        if let existing = try model(id: record.id) {
            existing.apply(record)
        } else {
            modelContext.insert(ImportModel(record))
        }
        try modelContext.save()
    }

    func remove(id: ImportID) async throws {
        guard let existing = try model(id: id) else { return }
        modelContext.delete(existing)
        try modelContext.save()
    }

    private func model(id: ImportID) throws -> ImportModel? {
        let rawID = id.rawValue
        var descriptor = FetchDescriptor<ImportModel>(predicate: #Predicate { $0.id == rawID })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
