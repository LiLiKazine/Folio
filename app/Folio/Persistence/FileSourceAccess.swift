import FolioCore
import Foundation

/// `SourceAccess` backed by security-scoped bookmarks, so a Failed Import can be retried later.
struct FileSourceAccess: SourceAccess, Sendable {
    /// How long to wait for an iCloud placeholder to download.
    private static let downloadTimeout: Duration = .seconds(60)
    private static let pollInterval: Duration = .milliseconds(500)

    #if os(macOS)
        private static let creationOptions: URL.BookmarkCreationOptions = .withSecurityScope
        private static let resolutionOptions: URL.BookmarkResolutionOptions = .withSecurityScope
    #else
        private static let creationOptions: URL.BookmarkCreationOptions = []
        private static let resolutionOptions: URL.BookmarkResolutionOptions = []
    #endif

    init() {}

    func bookmark(for url: URL) throws(SourceAccessError) -> Data {
        do {
            return try url.bookmarkData(
                options: Self.creationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            AppLog.persistence.error("Bookmark creation failed: \(error, privacy: .public)")
            throw .unavailable
        }
    }

    func withAccess<T: Sendable>(
        to bookmark: Data, _ body: @Sendable (URL) async throws -> T
    ) async throws -> T {
        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: bookmark, options: Self.resolutionOptions,
                relativeTo: nil, bookmarkDataIsStale: &isStale)
        } catch {
            AppLog.persistence.error("Bookmark resolution failed: \(error, privacy: .public)")
            throw SourceAccessError.unavailable
        }
        if isStale {
            AppLog.persistence.notice("Bookmark is stale; continuing with the resolved URL")
        }

        // False when no scope is needed (for example iOS container paths); that is fine.
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SourceAccessError.unavailable
        }
        try await ensureDownloaded(url)
        return try await body(url)
    }

    private func ensureDownloaded(_ url: URL) async throws {
        guard try isPlaceholder(url) else { return }
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            AppLog.persistence.error("Starting iCloud download failed: \(error, privacy: .public)")
            throw SourceAccessError.notDownloaded
        }
        let deadline = ContinuousClock.now + Self.downloadTimeout
        while try isPlaceholder(url) {
            guard ContinuousClock.now < deadline else { throw SourceAccessError.notDownloaded }
            try await Task.sleep(for: Self.pollInterval)
        }
    }

    /// True when the item is an iCloud item that is not fully downloaded.
    private func isPlaceholder(_ url: URL) throws -> Bool {
        let status = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            .ubiquitousItemDownloadingStatus
        guard let status else { return false }
        return status != .current
    }
}
