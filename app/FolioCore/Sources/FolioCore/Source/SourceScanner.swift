import Foundation

public enum SourceScanner {
    public static let pageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "webp", "gif"]

    /// Page files under `folder`, recursive, flattened, in reading order.
    /// Keeps only regular files (no directories or symbolic links) with a Page
    /// extension, and skips hidden files and anything under a `__MACOSX` directory
    /// inside `folder`.
    public static func pageFiles(in folder: URL) throws -> [URL] {
        let root = folder.resolvingSymlinksInPath()
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )
        else { return [] }

        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var entries: [(relativePath: String, url: URL)] = []
        for case let url as URL in enumerator {
            guard pageExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let relativePath = String(
                url.resolvingSymlinksInPath().path.dropFirst(rootPrefix.count))
            guard !relativePath.split(separator: "/").contains("__MACOSX") else { continue }
            entries.append((relativePath, url))
        }
        return
            entries
            .sorted {
                $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }
            .map(\.url)
    }

    /// Whether the picked item is a zip: its extension is `zip` or `cbz`, in any case.
    /// A `.cbz` is a zip under another name; Folio reads both the same way.
    public static func isZip(_ url: URL) -> Bool {
        ["zip", "cbz"].contains(url.pathExtension.lowercased())
    }

    /// Title for a picked item: last path component, minus a trailing `.zip` or `.cbz`.
    /// A folder name is returned unchanged, so `Vol.3` stays `Vol.3`.
    public static func title(forSource url: URL) -> String {
        guard isZip(url) else { return url.lastPathComponent }
        return url.deletingPathExtension().lastPathComponent
    }
}
