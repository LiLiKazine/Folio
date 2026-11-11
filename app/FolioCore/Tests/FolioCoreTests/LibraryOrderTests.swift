import Foundation
import Testing

@testable import FolioCore

@Suite("Library Order")
struct LibraryOrderTests {
    private func book(
        _ title: String, imported: TimeInterval, opened: TimeInterval? = nil, id: UUID = UUID()
    ) -> Book {
        Book(
            id: BookID(id), title: title, folderName: id.uuidString,
            pages: [Page(fileName: "001.jpg")], coverFileName: "cover.jpg",
            importedAt: Date(timeIntervalSince1970: imported),
            lastOpenedAt: opened.map { Date(timeIntervalSince1970: $0) }, readingPosition: nil)
    }

    private func record(_ status: ImportStatus, createdAt: TimeInterval) -> Import {
        Import(
            id: ImportID(), status: status, sourceBookmark: Data(), sourceName: "Source",
            title: "Title", pagesDone: 0, pagesTotal: nil, failureReason: nil, bookID: nil,
            createdAt: Date(timeIntervalSince1970: createdAt), finishedAt: nil)
    }

    @Test("the starting Library Order is Recent, Descending")
    func initial() {
        #expect(LibraryOrder.initial == LibraryOrder(sort: .recent, direction: .descending))
    }

    @Test("Recent orders by the last open, or the Import when never opened")
    func recent() {
        let books = [
            book("A", imported: 10), book("B", imported: 30), book("C", imported: 20, opened: 40),
        ]
        #expect(
            books.ordered(by: .init(sort: .recent, direction: .descending)).map(\.title)
                == ["C", "B", "A"])
        #expect(
            books.ordered(by: .init(sort: .recent, direction: .ascending)).map(\.title)
                == ["A", "B", "C"])
    }

    @Test("Title ignores case and counts numbers as numbers")
    func title() {
        let books = [
            book("Vol 10", imported: 1), book("vol 2", imported: 2), book("Vol 3", imported: 3),
        ]
        #expect(
            books.ordered(by: .init(sort: .title, direction: .ascending)).map(\.title)
                == ["vol 2", "Vol 3", "Vol 10"])
        #expect(
            books.ordered(by: .init(sort: .title, direction: .descending)).map(\.title)
                == ["Vol 10", "Vol 3", "vol 2"])
    }

    @Test("Date Imported ignores opens")
    func dateImported() {
        let books = [
            book("A", imported: 10, opened: 99), book("B", imported: 30), book("C", imported: 20),
        ]
        #expect(
            books.ordered(by: .init(sort: .dateImported, direction: .descending)).map(\.title)
                == ["B", "C", "A"])
        #expect(
            books.ordered(by: .init(sort: .dateImported, direction: .ascending)).map(\.title)
                == ["A", "C", "B"])
    }

    @Test("the same Title falls back to Date Imported, and the same time to the identifier")
    func ties() {
        let early = book("Vol 1", imported: 10)
        let late = book("Vol 1", imported: 20)
        #expect(
            [late, early].ordered(by: .init(sort: .title, direction: .ascending)).map(\.id)
                == [early.id, late.id])
        let low = book(
            "X", imported: 5, id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let high = book(
            "X", imported: 5, id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        for sort in LibraryOrder.Sort.allCases {
            #expect(
                [high, low].ordered(by: .init(sort: sort, direction: .ascending)).map(\.id)
                    == [low.id, high.id])
        }
    }

    @Test(
        "Descending is Ascending read from the other end, for every Sort and whatever order the array starts in",
        arguments: LibraryOrder.Sort.allCases)
    func descendingIsAscendingFromTheOtherEnd(sort: LibraryOrder.Sort) {
        // Six Books: two share a Title, two share an imported time, one was opened.
        let books = [
            book("Vol 1", imported: 10),
            book("Vol 1", imported: 20),
            book("alpha", imported: 30),
            book("Beta", imported: 30),
            book("Vol 10", imported: 40, opened: 5),
            book("Vol 2", imported: 50),
        ]
        let ascending = books.ordered(by: .init(sort: sort, direction: .ascending))
        #expect(
            books.ordered(by: .init(sort: sort, direction: .descending))
                == ascending.reversed())
        #expect(books.reversed().ordered(by: .init(sort: sort, direction: .ascending)) == ascending)
    }

    @Test(
        "Imports stay first under every Library Order: In Progress, Queued, Failed, then Books",
        arguments: LibraryOrder.Sort.allCases, LibraryOrder.Direction.allCases)
    func importsFirst(sort: LibraryOrder.Sort, direction: LibraryOrder.Direction) {
        let order = LibraryOrder(sort: sort, direction: direction)
        let inProgress = record(.inProgress, createdAt: 400)
        let queuedEarlier = record(.queued, createdAt: 100)
        let queuedLater = record(.queued, createdAt: 200)
        let failed = record(.failed, createdAt: 50)
        let books = [book("Zeta", imported: 1), book("Alpha", imported: 2, opened: 3)]
        let items: [LibraryItem] =
            [.book(books[0]), .importRecord(failed), .importRecord(queuedLater)]
            + [.book(books[1]), .importRecord(inProgress), .importRecord(queuedEarlier)]
        #expect(
            items.inLibraryOrder(order).map(\.id)
                == ([inProgress, queuedEarlier, queuedLater, failed].map {
                    LibraryItem.importRecord($0).id
                })
                + books.ordered(by: order).map { LibraryItem.book($0).id })
    }

    @Test("the in-memory Library Order repository has none until one is saved")
    func inMemoryRepository() async throws {
        let repository = InMemoryLibraryOrderRepository()
        #expect(try await repository.libraryOrder() == nil)
        let order = LibraryOrder(sort: .title, direction: .ascending)
        try await repository.save(order)
        #expect(try await repository.libraryOrder() == order)
        let other = LibraryOrder(sort: .dateImported, direction: .descending)
        try await repository.save(other)
        #expect(try await repository.libraryOrder() == other)
    }

    @Test("the failing Library Order repository throws for the calls it is told to fail")
    func failingRepository() async throws {
        let repository = FailingLibraryOrderRepository()
        let order = LibraryOrder(sort: .title, direction: .ascending)
        try await repository.save(order)

        await repository.fail([.libraryOrder])
        await #expect(throws: RepositoryFailure.self) { try await repository.libraryOrder() }
        try await repository.save(order)

        await repository.fail([.saveLibraryOrder])
        await #expect(throws: RepositoryFailure.self) {
            try await repository.save(.initial)
        }
        #expect(try await repository.libraryOrder() == order)

        await repository.succeed()
        try await repository.save(.initial)
        #expect(try await repository.libraryOrder() == .initial)
    }
}
