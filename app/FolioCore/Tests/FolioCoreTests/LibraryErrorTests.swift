import Foundation
import Testing

@testable import FolioCore

@Suite("Library errors are presentable")
struct LibraryErrorTests {
    private struct Fixture {
        let directory: TemporaryDirectory
        let books = FailingBookRepository()
        let imports = FailingImportRepository()
        let library: Library

        init(sourceAccess: InMemorySourceAccess = InMemorySourceAccess()) throws {
            directory = try TemporaryDirectory()
            library = Library(
                books: books, imports: imports,
                pipeline: ImportPipeline(
                    booksDirectory: directory.url.appending(
                        path: "Books", directoryHint: .isDirectory),
                    storage: FixedStorageCapacity(bytes: .max),
                    temporaryDirectory: directory.url.appending(
                        path: "Temp", directoryHint: .isDirectory),
                    stagingRootProvider: ImportPipeline.itemReplacementDirectory(for:)),
                sourceAccess: sourceAccess)
        }

        func addBook() async throws -> Book {
            let id = BookID()
            let book = Book(
                id: id, title: "Book", folderName: id.rawValue.uuidString,
                pages: [Page(fileName: "0001.png")],
                coverFileName: CoverImage.fileName, importedAt: .now, lastOpenedAt: nil,
                readingPosition: nil)
            try await books.add(book)
            return book
        }

        func addImport(status: ImportStatus) async throws -> Import {
            let record = Import(
                id: ImportID(), status: status, sourceBookmark: Data(), sourceName: "Source",
                title: "Source", pagesDone: 0, pagesTotal: nil,
                failureReason: status == .failed ? .noImagesFound : nil, bookID: nil,
                createdAt: .now, finishedAt: status == .failed ? .now : nil)
            try await imports.add(record)
            return record
        }

        /// Runs the public operation that `operation` names: against `book`, against
        /// a Queued Import to cancel, or against a Failed Import to retry or remove.
        func perform(
            _ operation: LibraryOperation, on book: Book, queued: Import, failed: Import
        ) async throws(LibraryError) {
            switch operation {
            case .import:
                _ = try await library.createImport(
                    from: directory.url.appending(path: "Source", directoryHint: .isDirectory))
            case .cancelImport: try await library.cancelImport(id: queued.id)
            case .retryImport: try await library.retryImport(id: failed.id)
            case .removeImport: try await library.removeImport(id: failed.id)
            case .rename: try await library.rename(bookID: book.id, to: "Renamed")
            case .open: try await library.open(bookID: book.id)
            case .deleteBook: try await library.removeBook(id: book.id)
            case .updateLibrary, .openLibrary:
                Issue.record("No operation set up for \(operation.rawValue)")
            }
        }
    }

    /// Which repository a storage case fails.
    enum Store: Sendable { case books, imports }

    /// One operation and the single repository write it depends on.
    struct StorageCase: Sendable, CustomTestStringConvertible {
        let operation: LibraryOperation
        let store: Store
        let call: RepositoryCall
        var testDescription: String { "\(operation.rawValue) → \(store).\(call)" }
    }

    @Test("rename with an empty Title throws emptyTitle")
    func emptyTitle() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        let book = try await fixture.addBook()

        await #expect(throws: LibraryError.emptyTitle) {
            try await fixture.library.rename(bookID: book.id, to: " \n")
        }
    }

    @Test("rename of an unknown Book throws notFound(.rename)")
    func renameNotFound() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }

        await #expect(throws: LibraryError.notFound(.rename)) {
            try await fixture.library.rename(bookID: BookID(), to: "Title")
        }
    }

    @Test("retry of a Queued Import throws invalidStatus(.retryImport)")
    func retryInvalid() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        let queued = Import(
            id: ImportID(), status: .queued, sourceBookmark: Data(), sourceName: "Source",
            title: "Source", pagesDone: 0, pagesTotal: nil, failureReason: nil, bookID: nil,
            createdAt: .now, finishedAt: nil)
        try await fixture.imports.add(queued)

        await #expect(throws: LibraryError.invalidStatus(.retryImport)) {
            try await fixture.library.retryImport(id: queued.id)
        }
    }

    @Test("createImport with an unavailable Source throws sourceUnavailable with the Source name")
    func createUnavailable() async throws {
        let source = URL(fileURLWithPath: "/tmp/Folio/Chapter 01", isDirectory: true)
        var access = InMemorySourceAccess()
        access.unbookmarkable.insert(source.path)
        let fixture = try Fixture(sourceAccess: access)
        defer { fixture.directory.remove() }

        await #expect(throws: LibraryError.sourceUnavailable(sourceName: "Chapter 01")) {
            _ = try await fixture.library.createImport(from: source)
        }
    }

    @Test(
        "a repository write failure surfaces as storage(operation)",
        arguments: [
            StorageCase(operation: .import, store: .imports, call: .add),
            StorageCase(operation: .cancelImport, store: .imports, call: .update),
            StorageCase(operation: .retryImport, store: .imports, call: .update),
            StorageCase(operation: .removeImport, store: .imports, call: .remove),
            StorageCase(operation: .rename, store: .books, call: .update),
            StorageCase(operation: .open, store: .books, call: .update),
            StorageCase(operation: .deleteBook, store: .books, call: .remove),
        ])
    func storage(_ storageCase: StorageCase) async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        let book = try await fixture.addBook()
        let queued = try await fixture.addImport(status: .queued)
        let failed = try await fixture.addImport(status: .failed)
        switch storageCase.store {
        case .books: await fixture.books.fail([storageCase.call])
        case .imports: await fixture.imports.fail([storageCase.call])
        }

        await #expect(throws: LibraryError.storage(storageCase.operation)) {
            try await fixture.perform(
                storageCase.operation, on: book, queued: queued, failed: failed)
        }
    }

    @Test("items() with a failing read throws storage(.updateLibrary)")
    func itemsRead() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        await fixture.books.fail([.allBooks])

        await #expect(throws: LibraryError.storage(.updateLibrary)) {
            _ = try await fixture.library.items()
        }
    }

    @Test("failing repositories recover after succeed()")
    func succeedAfterFail() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        let book = try await fixture.addBook()
        await fixture.books.fail([.update])
        await fixture.books.succeed()

        try await fixture.library.rename(bookID: book.id, to: "Renamed")
        #expect(try await fixture.books.book(id: book.id)?.title == "Renamed")
    }

    @Test("every LibraryError has an operation")
    func operations() {
        let expected: [(LibraryError, LibraryOperation)] =
            [
                (.emptyTitle, .rename),
                (.sourceUnavailable(sourceName: "Chapter 01"), .import),
                (.sourceNotDownloaded(sourceName: "Chapter 01"), .import),
            ]
            + LibraryOperation.allCases.flatMap { op in
                [(.notFound(op), op), (.invalidStatus(op), op), (.storage(op), op)]
            }
        for (error, operation) in expected {
            #expect(error.operation == operation)
        }
    }
}
