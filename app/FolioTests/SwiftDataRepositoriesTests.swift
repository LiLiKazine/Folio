import FolioCore
import Foundation
import Testing

@testable import Folio

@Suite("SwiftData repositories")
@MainActor struct SwiftDataRepositoriesTests {
    private func makeBook(
        id: BookID = BookID(),
        pages: [String] = ["0001.jpg"],
        importedAt: Date,
        lastOpenedAt: Date? = nil,
        readingPosition: Int? = nil
    ) -> Book {
        Book(
            id: id,
            title: "Title",
            folderName: id.rawValue.uuidString,
            pages: pages.map { Page(fileName: $0) },
            coverFileName: "cover.jpg",
            importedAt: importedAt,
            lastOpenedAt: lastOpenedAt,
            readingPosition: readingPosition
        )
    }

    private func makeImport(
        status: ImportStatus,
        createdAt: Date,
        failureReason: ImportFailureReason? = nil,
        bookID: BookID? = nil
    ) -> Import {
        Import(
            id: ImportID(),
            status: status,
            sourceBookmark: Data([0x01, 0x02, 0x03]),
            sourceName: "Source.zip",
            title: "Source",
            pagesDone: 3,
            pagesTotal: 7,
            failureReason: failureReason,
            bookID: bookID,
            createdAt: createdAt,
            finishedAt: nil
        )
    }

    @Test("Book roundtrips with explicit Page order") func bookRoundtrip() async throws {
        let repository = SwiftDataBookRepository(
            modelContainer: try LibraryStorage.makeContainer(inMemory: true))
        let book = makeBook(
            pages: ["0002.jpg", "0001.jpg", "0010.jpg"],
            importedAt: Date(timeIntervalSince1970: 1_000),
            lastOpenedAt: Date(timeIntervalSince1970: 2_000),
            readingPosition: 1
        )

        try await repository.add(book)
        let fetched = try await repository.book(id: book.id)

        #expect(fetched == book)
        #expect(fetched?.pages.map(\.fileName) == ["0002.jpg", "0001.jpg", "0010.jpg"])

        var renamed = book
        renamed.title = "Renamed"
        renamed.readingPosition = 2
        try await repository.update(renamed)
        #expect(try await repository.book(id: book.id) == renamed)

        try await repository.remove(id: book.id)
        #expect(try await repository.book(id: book.id) == nil)
    }

    @Test("allBooks uses Library order") func order() async throws {
        let repository = SwiftDataBookRepository(
            modelContainer: try LibraryStorage.makeContainer(inMemory: true))
        let older = makeBook(importedAt: Date(timeIntervalSince1970: 1_000))
        let newer = makeBook(importedAt: Date(timeIntervalSince1970: 2_000))
        let opened = makeBook(
            importedAt: Date(timeIntervalSince1970: 500),
            lastOpenedAt: Date(timeIntervalSince1970: 3_000)
        )
        let tieA = makeBook(importedAt: Date(timeIntervalSince1970: 1_500))
        let tieB = makeBook(importedAt: Date(timeIntervalSince1970: 1_500))
        for book in [older, tieA, opened, newer, tieB] { try await repository.add(book) }

        let ties = [tieA, tieB].sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        #expect(
            try await repository.allBooks().map(\.id)
                == [opened, newer, ties[0], ties[1], older].map(\.id))
    }

    @Test("Import roundtrips status, reason and bookID") func importRoundtrip() async throws {
        let repository = SwiftDataImportRepository(
            modelContainer: try LibraryStorage.makeContainer(inMemory: true))
        let failed = makeImport(
            status: .failed,
            createdAt: Date(timeIntervalSince1970: 1_000),
            failureReason: .notEnoughStorage,
            bookID: BookID()
        )
        let inProgress = makeImport(
            status: .inProgress, createdAt: Date(timeIntervalSince1970: 2_000), bookID: BookID())

        try await repository.add(failed)
        try await repository.add(inProgress)
        #expect(try await repository.importRecord(id: failed.id) == failed)
        #expect(try await repository.importRecord(id: inProgress.id) == inProgress)

        var completed = inProgress
        completed.status = .completed
        completed.pagesDone = 7
        completed.finishedAt = Date(timeIntervalSince1970: 3_000)
        try await repository.update(completed)
        #expect(try await repository.importRecord(id: inProgress.id) == completed)

        try await repository.remove(id: failed.id)
        #expect(try await repository.importRecord(id: failed.id) == nil)
    }

    @Test("imports(status:) filters") func filter() async throws {
        let repository = SwiftDataImportRepository(
            modelContainer: try LibraryStorage.makeContainer(inMemory: true))
        let laterQueued = makeImport(status: .queued, createdAt: Date(timeIntervalSince1970: 3_000))
        let earlierQueued = makeImport(
            status: .queued, createdAt: Date(timeIntervalSince1970: 1_000))
        let failed = makeImport(
            status: .failed, createdAt: Date(timeIntervalSince1970: 2_000),
            failureReason: .cancelled)
        for record in [laterQueued, failed, earlierQueued] { try await repository.add(record) }

        #expect(
            try await repository.imports(status: .queued).map(\.id) == [
                earlierQueued.id, laterQueued.id,
            ])
        #expect(try await repository.imports(status: .failed).map(\.id) == [failed.id])
        #expect(try await repository.imports(status: .completed).isEmpty)
    }

    @Test("booksDirectory is excluded from backup") func backupExclusion() throws {
        let url = try LibraryStorage.booksDirectory()
        #expect(url.lastPathComponent == "Books")
        #expect(
            try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
        )
    }
}
