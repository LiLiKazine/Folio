import Foundation

public struct ImportID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public enum ImportStatus: String, Codable, Sendable { case queued, inProgress, failed, completed }

public enum ImportFailureReason: String, Codable, Sendable, Equatable {
    case noImagesFound, unreadableZip, unsupportedZip, sourceNotDownloaded,
        notEnoughStorage, sourceUnavailable, cancelled
}

public struct Import: Hashable, Codable, Sendable, Identifiable {
    public let id: ImportID
    public var status: ImportStatus
    public let sourceBookmark: Data
    /// Display name of the picked item.
    public let sourceName: String
    /// Title the Book will get.
    public let title: String
    public var pagesDone: Int
    public var pagesTotal: Int?
    public var failureReason: ImportFailureReason?
    public var bookID: BookID?
    public let createdAt: Date
    public var finishedAt: Date?

    public init(
        id: ImportID,
        status: ImportStatus,
        sourceBookmark: Data,
        sourceName: String,
        title: String,
        pagesDone: Int,
        pagesTotal: Int?,
        failureReason: ImportFailureReason?,
        bookID: BookID?,
        createdAt: Date,
        finishedAt: Date?
    ) {
        self.id = id
        self.status = status
        self.sourceBookmark = sourceBookmark
        self.sourceName = sourceName
        self.title = title
        self.pagesDone = pagesDone
        self.pagesTotal = pagesTotal
        self.failureReason = failureReason
        self.bookID = bookID
        self.createdAt = createdAt
        self.finishedAt = finishedAt
    }
}
