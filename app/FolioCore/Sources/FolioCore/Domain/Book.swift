import Foundation

public struct BookID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public struct Page: Hashable, Codable, Sendable {
    public let fileName: String

    public init(fileName: String) { self.fileName = fileName }
}

public struct Book: Hashable, Codable, Sendable, Identifiable {
    public let id: BookID
    public var title: String
    /// Directory under the Books directory.
    public let folderName: String
    /// Reading order, explicit.
    public let pages: [Page]
    /// Rendered Cover image inside `folderName`.
    public let coverFileName: String
    public let importedAt: Date
    public var lastOpenedAt: Date?
    /// Index into `pages`.
    public var readingPosition: Int?

    public init(
        id: BookID,
        title: String,
        folderName: String,
        pages: [Page],
        coverFileName: String,
        importedAt: Date,
        lastOpenedAt: Date?,
        readingPosition: Int?
    ) {
        self.id = id
        self.title = title
        self.folderName = folderName
        self.pages = pages
        self.coverFileName = coverFileName
        self.importedAt = importedAt
        self.lastOpenedAt = lastOpenedAt
        self.readingPosition = readingPosition
    }
}

extension Array where Element == Book {
    /// Library order: last opened or imported, newest first.
    public func inLibraryOrder() -> [Book] {
        sorted { ($0.lastOpenedAt ?? $0.importedAt) > ($1.lastOpenedAt ?? $1.importedAt) }
    }
}
