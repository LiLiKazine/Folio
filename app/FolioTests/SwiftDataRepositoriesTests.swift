import FolioCore
import Foundation
import SwiftData
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

    @Test("a Book's Reading Mode roundtrips") func readingModeRoundtrips() async throws {
        let repository = SwiftDataBookRepository(
            modelContainer: try LibraryStorage.makeContainer(inMemory: true))
        var book = makeBook(importedAt: Date(timeIntervalSince1970: 1_000))
        book.readingMode = .vertical

        try await repository.add(book)
        #expect(try await repository.book(id: book.id)?.readingMode == .vertical)

        book.readingMode = .pageByPage
        try await repository.update(book)
        #expect(try await repository.book(id: book.id)?.readingMode == .pageByPage)
    }

    @Test("a stored Reading Mode that names no case reads as Page by Page")
    func unknownReadingModeIsPageByPage() {
        let model = BookModel(makeBook(importedAt: Date(timeIntervalSince1970: 1_000)))

        model.readingMode = "scroll"

        #expect(model.book.readingMode == .pageByPage)
    }

    @Test("a store written by the first schema opens in the current one, as Page by Page")
    func v1StoreOpensAsPageByPage() async throws {
        // This also passes with no migration stages: it shows the old store opens, not that
        // the stage is what opens it.
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Library.store", directoryHint: .notDirectory)
        let id = UUID()
        let importedAt = Date(timeIntervalSince1970: 1_000)

        do {
            let v1 = try ModelContainer(
                for: Schema(versionedSchema: FolioSchemaV1.self),
                configurations: [
                    ModelConfiguration(
                        schema: Schema(versionedSchema: FolioSchemaV1.self), url: storeURL)
                ])
            let context = ModelContext(v1)
            context.insert(
                FolioSchemaV1.BookModel(
                    id: id, title: "Old Book", folderName: id.uuidString,
                    pageFileNames: ["0001.jpg", "0002.jpg"], coverFileName: "cover.jpg",
                    importedAt: importedAt, lastOpenedAt: nil, readingPosition: 1))
            try context.save()
        }

        let repository = SwiftDataBookRepository(
            modelContainer: try LibraryStorage.makeContainer(at: storeURL))
        let books = try await repository.allBooks()

        #expect(books.count == 1)
        #expect(books.first?.id == BookID(id))
        #expect(books.first?.title == "Old Book")
        #expect(books.first?.pages.map(\.fileName) == ["0001.jpg", "0002.jpg"])
        #expect(books.first?.readingPosition == 1)
        #expect(books.first?.readingMode == .pageByPage)
    }

    @Test(
        "a store written by the second schema opens in the current one, with its Book and no Library Order"
    )
    func v2StoreOpensWithNoLibraryOrder() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Library.store", directoryHint: .notDirectory)
        let book = Book(
            id: BookID(), title: "Second Schema Book", folderName: "folder",
            pages: [Page(fileName: "0001.jpg"), Page(fileName: "0002.jpg")],
            coverFileName: "cover.jpg", importedAt: Date(timeIntervalSince1970: 1_000),
            lastOpenedAt: nil, readingPosition: 1, readingMode: .vertical)

        do {
            let schema = Schema(versionedSchema: FolioSchemaV2.self)
            let v2 = try ModelContainer(
                for: schema, configurations: [ModelConfiguration(schema: schema, url: storeURL)])
            let context = ModelContext(v2)
            context.insert(BookModel(book))
            try context.save()
        }

        let container = try LibraryStorage.makeContainer(at: storeURL)
        let books = try await SwiftDataBookRepository(modelContainer: container).allBooks()

        #expect(books.count == 1)
        #expect(books.first?.id == book.id)
        #expect(books.first?.title == "Second Schema Book")
        #expect(books.first?.pages.map(\.fileName) == ["0001.jpg", "0002.jpg"])
        #expect(books.first?.readingPosition == 1)
        #expect(books.first?.readingMode == .vertical)
        #expect(
            try await SwiftDataLibraryOrderRepository(modelContainer: container).libraryOrder()
                == nil)
    }

    @Test("nothing saved reads as no Library Order") func noLibraryOrderSaved() async throws {
        let repository = SwiftDataLibraryOrderRepository(
            modelContainer: try LibraryStorage.makeContainer(inMemory: true))

        #expect(try await repository.libraryOrder() == nil)
    }

    @Test("the Library Order roundtrips, and a second save replaces the first")
    func libraryOrderRoundtrip() async throws {
        let container = try LibraryStorage.makeContainer(inMemory: true)
        let repository = SwiftDataLibraryOrderRepository(modelContainer: container)

        try await repository.save(LibraryOrder(sort: .title, direction: .ascending))
        #expect(
            try await repository.libraryOrder()
                == LibraryOrder(sort: .title, direction: .ascending))

        try await repository.save(LibraryOrder(sort: .dateImported, direction: .descending))
        #expect(
            try await repository.libraryOrder()
                == LibraryOrder(sort: .dateImported, direction: .descending))
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<LibraryOrderModel>()) == 1)
    }

    @Test("a stored Library Order that names no case reads as Recent, Descending")
    func unknownLibraryOrderReadsAsInitial() {
        let unknownSort = LibraryOrderModel(.initial)
        unknownSort.sort = "pageCount"
        #expect(unknownSort.libraryOrder == .initial)

        let unknownDirection = LibraryOrderModel(LibraryOrder(sort: .title, direction: .ascending))
        unknownDirection.direction = "sideways"
        #expect(unknownDirection.libraryOrder == .initial)
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
