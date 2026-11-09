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
    /// How this Book is read. Books stored before Reading Modes existed read Page by Page.
    public var readingMode: ReadingMode

    public init(
        id: BookID,
        title: String,
        folderName: String,
        pages: [Page],
        coverFileName: String,
        importedAt: Date,
        lastOpenedAt: Date?,
        readingPosition: Int?,
        readingMode: ReadingMode = .pageByPage
    ) {
        self.id = id
        self.title = title
        self.folderName = folderName
        self.pages = pages
        self.coverFileName = coverFileName
        self.importedAt = importedAt
        self.lastOpenedAt = lastOpenedAt
        self.readingPosition = readingPosition
        self.readingMode = readingMode
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(BookID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        folderName = try values.decode(String.self, forKey: .folderName)
        pages = try values.decode([Page].self, forKey: .pages)
        coverFileName = try values.decode(String.self, forKey: .coverFileName)
        importedAt = try values.decode(Date.self, forKey: .importedAt)
        lastOpenedAt = try values.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
        readingPosition = try values.decodeIfPresent(Int.self, forKey: .readingPosition)
        readingMode =
            try values.decodeIfPresent(ReadingMode.self, forKey: .readingMode) ?? .pageByPage
    }
}

extension Array where Element == Book {
    /// Library order: last opened or imported, newest first.
    public func inLibraryOrder() -> [Book] {
        sorted { ($0.lastOpenedAt ?? $0.importedAt) > ($1.lastOpenedAt ?? $1.importedAt) }
    }
}
