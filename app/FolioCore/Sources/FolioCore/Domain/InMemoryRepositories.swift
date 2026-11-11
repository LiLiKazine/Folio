public actor InMemoryBookRepository: BookRepository {
    private var books: [BookID: Book] = [:]

    public init() {}

    public func allBooks() async throws -> [Book] {
        Array(books.values).inLibraryOrder()
    }

    public func book(id: BookID) async throws -> Book? { books[id] }

    public func add(_ book: Book) async throws { books[book.id] = book }

    public func update(_ book: Book) async throws { books[book.id] = book }

    public func remove(id: BookID) async throws { books[id] = nil }
}

public actor InMemoryImportRepository: ImportRepository {
    private var records: [ImportID: Import] = [:]

    public init() {}

    public func imports(status: ImportStatus) async throws -> [Import] {
        records.values.filter { $0.status == status }.sorted { $0.createdAt < $1.createdAt }
    }

    public func importRecord(id: ImportID) async throws -> Import? { records[id] }

    public func add(_ record: Import) async throws { records[record.id] = record }

    public func update(_ record: Import) async throws { records[record.id] = record }

    public func remove(id: ImportID) async throws { records[id] = nil }
}

public actor InMemoryLibraryOrderRepository: LibraryOrderRepository {
    private var order: LibraryOrder?

    public init() {}

    public func libraryOrder() async throws -> LibraryOrder? { order }

    public func save(_ order: LibraryOrder) async throws { self.order = order }
}
