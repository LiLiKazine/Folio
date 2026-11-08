import FolioCore
import Foundation

/// `SourceAccess` backed by security-scoped bookmarks, so a Failed Import can be retried later.
struct FileSourceAccess: SourceAccess, Sendable {
    private static let pollInterval: Duration = .milliseconds(500)

    #if os(macOS)
        private static let creationOptions: URL.BookmarkCreationOptions = .withSecurityScope
        private static let resolutionOptions: URL.BookmarkResolutionOptions = .withSecurityScope
    #else
        private static let creationOptions: URL.BookmarkCreationOptions = []
        private static let resolutionOptions: URL.BookmarkResolutionOptions = []
    #endif

    /// How long to wait, in total, for a Source's iCloud files to download.
    private let downloadTimeout: Duration

    init(downloadTimeout: Duration = .seconds(60)) {
        self.downloadTimeout = downloadTimeout
    }

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

    /// Makes sure the Source and, for a folder, every file inside it are downloaded
    /// from iCloud: starts each pending download, then polls until all are current
    /// or the timeout passes. Items outside iCloud have no status and pass at once.
    private func ensureDownloaded(_ url: URL) async throws {
        let pending = try pendingDownloads(in: url)
        guard !pending.isEmpty else { return }
        for item in pending {
            do {
                try FileManager.default.startDownloadingUbiquitousItem(at: item.requestURL)
            } catch {
                AppLog.persistence.error(
                    "Starting iCloud download failed: \(error, privacy: .public)")
                throw SourceAccessError.notDownloaded
            }
        }
        let deadline = ContinuousClock.now + downloadTimeout
        var waiting = pending
        while true {
            waiting = try waiting.filter { try !$0.isDownloaded() }
            if waiting.isEmpty { return }
            guard ContinuousClock.now < deadline else {
                AppLog.persistence.error(
                    "\(waiting.count, privacy: .public) Source files still not downloaded")
                throw SourceAccessError.notDownloaded
            }
            try await Task.sleep(for: Self.pollInterval)
        }
    }

    /// The items under `url` that iCloud has not fully downloaded. A folder is walked
    /// recursively: hidden files are skipped, except `.<name>.icloud` placeholders,
    /// which stand for `<name>` in the same folder.
    private func pendingDownloads(in url: URL) throws(SourceAccessError) -> [PendingDownload] {
        guard try Self.resourceValues(of: url, [.isDirectoryKey]).isDirectory == true else {
            return try PendingDownload.file(url).isDownloaded() ? [] : [.file(url)]
        }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: keys, options: [],
                errorHandler: { _, _ in true })
        else { throw SourceAccessError.unavailable }
        var pending: [PendingDownload] = []
        for case let file as URL in enumerator {
            let name = file.lastPathComponent
            if let target = PendingDownload.placeholderTarget(of: name) {
                pending.append(
                    .placeholder(
                        file, target: file.deletingLastPathComponent().appending(path: target)))
                continue
            }
            let values = try Self.resourceValues(of: file, Set(keys))
            guard values.isRegularFile == true, values.isHidden != true, !name.hasPrefix(".")
            else { continue }
            if try !PendingDownload.file(file).isDownloaded() {
                pending.append(.file(file))
            }
        }
        return pending
    }

    /// `resourceValues`, with any failure reported as an unavailable Source.
    fileprivate static func resourceValues(
        of url: URL, _ keys: Set<URLResourceKey>
    ) throws(SourceAccessError) -> URLResourceValues {
        do {
            return try url.resourceValues(forKeys: keys)
        } catch {
            AppLog.persistence.error("Reading Source attributes failed: \(error, privacy: .public)")
            throw .unavailable
        }
    }
}

/// One iCloud item a Source is waiting on.
private enum PendingDownload {
    /// A file whose downloading status is not current.
    case file(URL)
    /// A `.<name>.icloud` placeholder that becomes `target` once downloaded.
    case placeholder(URL, target: URL)

    /// The URL to pass to `startDownloadingUbiquitousItem`.
    var requestURL: URL {
        switch self {
        case .file(let url), .placeholder(let url, _): url
        }
    }

    /// `<name>` for a file named `.<name>.icloud`, else nil.
    static func placeholderTarget(of name: String) -> String? {
        let prefix = ".", suffix = ".icloud"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix),
            name.count > prefix.count + suffix.count
        else { return nil }
        return String(name.dropFirst(prefix.count).dropLast(suffix.count))
    }

    func isDownloaded() throws(SourceAccessError) -> Bool {
        let file: URL
        switch self {
        case .file(let url):
            file = url
        case .placeholder(let placeholder, let target):
            let manager = FileManager.default
            guard !manager.fileExists(atPath: placeholder.path),
                manager.fileExists(atPath: target.path)
            else { return false }
            file = target
        }
        let status = try FileSourceAccess.resourceValues(
            of: file, [.ubiquitousItemDownloadingStatusKey]
        ).ubiquitousItemDownloadingStatus
        guard let status else { return true }
        return status == .current
    }
}
