import FolioCore
import Foundation
import SwiftData

/// `BookRepository` backed by SwiftData. `BookModel`s never leave the actor.
@ModelActor
actor SwiftDataBookRepository: BookRepository {
    func allBooks() async throws -> [Book] {
        try modelContext.fetch(FetchDescriptor<BookModel>()).map(\.book)
    }

    func book(id: BookID) async throws -> Book? {
        try model(id: id)?.book
    }

    func add(_ book: Book) async throws {
        modelContext.insert(BookModel(book))
        try modelContext.save()
    }

    /// Inserts the Book if it is not stored yet.
    func update(_ book: Book) async throws {
        if let existing = try model(id: book.id) {
            existing.apply(book)
        } else {
            modelContext.insert(BookModel(book))
        }
        try modelContext.save()
    }

    func remove(id: BookID) async throws {
        guard let existing = try model(id: id) else { return }
        modelContext.delete(existing)
        try modelContext.save()
    }

    private func model(id: BookID) throws -> BookModel? {
        let rawID = id.rawValue
        var descriptor = FetchDescriptor<BookModel>(predicate: #Predicate { $0.id == rawID })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
