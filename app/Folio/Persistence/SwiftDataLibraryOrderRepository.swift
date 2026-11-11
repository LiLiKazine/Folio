import FolioCore
import Foundation
import SwiftData

/// `LibraryOrderRepository` backed by SwiftData. The Library Order is one row;
/// `LibraryOrderModel`s never leave the actor.
@ModelActor
actor SwiftDataLibraryOrderRepository: LibraryOrderRepository {
    func libraryOrder() async throws -> LibraryOrder? {
        try firstModel()?.libraryOrder
    }

    /// Updates the stored row, or inserts it when nothing was saved yet.
    func save(_ order: LibraryOrder) async throws {
        if let existing = try firstModel() {
            existing.apply(order)
        } else {
            modelContext.insert(LibraryOrderModel(order))
        }
        try modelContext.save()
    }

    private func firstModel() throws -> LibraryOrderModel? {
        var descriptor = FetchDescriptor<LibraryOrderModel>()
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
