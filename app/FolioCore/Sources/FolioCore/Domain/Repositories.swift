public protocol BookRepository: Sendable {
    /// All Books in Library order.
    func allBooks() async throws -> [Book]
    func book(id: BookID) async throws -> Book?
    func add(_ book: Book) async throws
    func update(_ book: Book) async throws
    func remove(id: BookID) async throws
}

public protocol ImportRepository: Sendable {
    /// Imports with the given status, `createdAt` ascending.
    func imports(status: ImportStatus) async throws -> [Import]
    func importRecord(id: ImportID) async throws -> Import?
    func add(_ record: Import) async throws
    func update(_ record: Import) async throws
    func remove(id: ImportID) async throws
}
