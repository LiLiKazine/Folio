/// A repository method a failing test double can be told to fail.
public enum RepositoryCall: Sendable {
    case allBooks, book, add, update, remove, imports, importRecord, libraryOrder, saveLibraryOrder
}

/// The error a failing test double throws for a call it was told to fail.
public struct RepositoryFailure: Error {
    public init() {}
}

/// Test double: an in-memory Book repository whose calls can be made to throw
/// `RepositoryFailure`, to show how the Library handles storage failures.
public actor FailingBookRepository: BookRepository {
    private let base: InMemoryBookRepository
    private var failing: Set<RepositoryCall> = []

    public init(base: InMemoryBookRepository = InMemoryBookRepository()) {
        self.base = base
    }

    /// From now on, the given calls throw `RepositoryFailure` without touching storage.
    public func fail(_ calls: Set<RepositoryCall>) { failing = calls }

    /// From now on, every call succeeds.
    public func succeed() { failing = [] }

    private func check(_ call: RepositoryCall) throws {
        if failing.contains(call) { throw RepositoryFailure() }
    }

    public func allBooks() async throws -> [Book] {
        try check(.allBooks)
        return try await base.allBooks()
    }

    public func book(id: BookID) async throws -> Book? {
        try check(.book)
        return try await base.book(id: id)
    }

    public func add(_ book: Book) async throws {
        try check(.add)
        try await base.add(book)
    }

    public func update(_ book: Book) async throws {
        try check(.update)
        try await base.update(book)
    }

    public func remove(id: BookID) async throws {
        try check(.remove)
        try await base.remove(id: id)
    }
}

/// Test double: an in-memory Import repository whose calls can be made to throw
/// `RepositoryFailure`, to show how the Library handles storage failures.
public actor FailingImportRepository: ImportRepository {
    private let base: InMemoryImportRepository
    private var failing: Set<RepositoryCall> = []

    public init(base: InMemoryImportRepository = InMemoryImportRepository()) {
        self.base = base
    }

    /// From now on, the given calls throw `RepositoryFailure` without touching storage.
    public func fail(_ calls: Set<RepositoryCall>) { failing = calls }

    /// From now on, every call succeeds.
    public func succeed() { failing = [] }

    private func check(_ call: RepositoryCall) throws {
        if failing.contains(call) { throw RepositoryFailure() }
    }

    public func imports(status: ImportStatus) async throws -> [Import] {
        try check(.imports)
        return try await base.imports(status: status)
    }

    public func importRecord(id: ImportID) async throws -> Import? {
        try check(.importRecord)
        return try await base.importRecord(id: id)
    }

    public func add(_ record: Import) async throws {
        try check(.add)
        try await base.add(record)
    }

    public func update(_ record: Import) async throws {
        try check(.update)
        try await base.update(record)
    }

    public func remove(id: ImportID) async throws {
        try check(.remove)
        try await base.remove(id: id)
    }
}

/// Test double: an in-memory Library Order repository whose calls can be made to throw
/// `RepositoryFailure`, to show how the Library handles storage failures.
public actor FailingLibraryOrderRepository: LibraryOrderRepository {
    private let base: InMemoryLibraryOrderRepository
    private var failing: Set<RepositoryCall> = []

    public init(base: InMemoryLibraryOrderRepository = InMemoryLibraryOrderRepository()) {
        self.base = base
    }

    /// From now on, the given calls throw `RepositoryFailure` without touching storage.
    public func fail(_ calls: Set<RepositoryCall>) { failing = calls }

    /// From now on, every call succeeds.
    public func succeed() { failing = [] }

    private func check(_ call: RepositoryCall) throws {
        if failing.contains(call) { throw RepositoryFailure() }
    }

    public func libraryOrder() async throws -> LibraryOrder? {
        try check(.libraryOrder)
        return try await base.libraryOrder()
    }

    public func save(_ order: LibraryOrder) async throws {
        try check(.saveLibraryOrder)
        try await base.save(order)
    }
}
