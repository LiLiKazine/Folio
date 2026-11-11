import Foundation
import Testing

@testable import FolioCore

@Suite("In-memory repositories")
struct InMemoryRepositoriesTests {
    @Test("allBooks returns every Book")
    func allBooks() async throws {
        let repo = InMemoryBookRepository()
        let old = makeBook(importedAt: .init(timeIntervalSince1970: 100))
        let opened = makeBook(
            importedAt: .init(timeIntervalSince1970: 50),
            lastOpenedAt: .init(timeIntervalSince1970: 500))
        let fresh = makeBook(importedAt: .init(timeIntervalSince1970: 300))
        for book in [old, opened, fresh] { try await repo.add(book) }
        #expect(Set(try await repo.allBooks().map(\.id)) == [opened.id, fresh.id, old.id])
    }

    @Test("update replaces a Book by id")
    func update() async throws {
        let repo = InMemoryBookRepository()
        var book = makeBook(importedAt: .init(timeIntervalSince1970: 100))
        try await repo.add(book)
        book.title = "Renamed"
        try await repo.update(book)
        #expect(try await repo.book(id: book.id)?.title == "Renamed")
        #expect(try await repo.allBooks().count == 1)
    }

    @Test("remove deletes by id")
    func remove() async throws {
        let repo = InMemoryBookRepository()
        let book = makeBook(importedAt: .init(timeIntervalSince1970: 100))
        try await repo.add(book)
        try await repo.remove(id: book.id)
        #expect(try await repo.book(id: book.id) == nil)
    }

    @Test("imports(status:) filters and orders by createdAt ascending")
    func importsByStatus() async throws {
        let repo = InMemoryImportRepository()
        let later = makeImport(status: .queued, createdAt: .init(timeIntervalSince1970: 200))
        let earlier = makeImport(status: .queued, createdAt: .init(timeIntervalSince1970: 100))
        let failed = makeImport(status: .failed, createdAt: .init(timeIntervalSince1970: 50))
        for record in [later, failed, earlier] { try await repo.add(record) }
        #expect(try await repo.imports(status: .queued).map(\.id) == [earlier.id, later.id])
        #expect(try await repo.importRecord(id: failed.id)?.status == .failed)
    }
}

private func makeBook(importedAt: Date, lastOpenedAt: Date? = nil) -> Book {
    Book(
        id: BookID(), title: "Book", folderName: UUID().uuidString,
        pages: [Page(fileName: "001.jpg")], coverFileName: "cover.jpg",
        importedAt: importedAt, lastOpenedAt: lastOpenedAt, readingPosition: nil)
}

private func makeImport(status: ImportStatus, createdAt: Date) -> Import {
    Import(
        id: ImportID(), status: status, sourceBookmark: Data(), sourceName: "Source",
        title: "Title", pagesDone: 0, pagesTotal: nil, failureReason: nil, bookID: nil,
        createdAt: createdAt, finishedAt: nil)
}
