import Foundation

public enum SourceAccessError: Error, Equatable {
    case unavailable
    case notDownloaded
}

/// Port for durable, security-scoped access to a user-picked source.
public protocol SourceAccess: Sendable {
    /// Bookmark for a URL the user just picked (while access is still granted by the picker).
    func bookmark(for url: URL) throws(SourceAccessError) -> Data
    /// Resolves a bookmark, ensures the item is downloaded, and runs `body` with access held.
    func withAccess<T: Sendable>(
        to bookmark: Data, _ body: @Sendable (URL) async throws -> T
    ) async throws -> T
}

/// Test double: the bookmark is the URL's path as UTF-8 data.
public struct InMemorySourceAccess: SourceAccess {
    /// Paths that should fail as `.unavailable`.
    public var unavailable: Set<String> = []

    public init() {}

    public func bookmark(for url: URL) throws(SourceAccessError) -> Data {
        Data(url.path.utf8)
    }

    public func withAccess<T: Sendable>(
        to bookmark: Data, _ body: @Sendable (URL) async throws -> T
    ) async throws -> T {
        guard let path = String(data: bookmark, encoding: .utf8), !unavailable.contains(path) else {
            throw SourceAccessError.unavailable
        }
        return try await body(URL(fileURLWithPath: path))
    }
}
