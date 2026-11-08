import Foundation

public enum SourceScanner {
    public static let pageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "webp", "gif"]

    /// Page files under `folder`, recursive, flattened, in reading order.
    /// Skips hidden files, anything under a `__MACOSX` directory, and non-Page extensions.
    public static func pageFiles(in folder: URL) throws -> [URL] {
        let root = folder.resolvingSymlinksInPath()
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        else { return [] }

        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var entries: [(relativePath: String, url: URL)] = []
        for case let url as URL in enumerator {
            guard !url.pathComponents.contains("__MACOSX"),
                pageExtensions.contains(url.pathExtension.lowercased())
            else { continue }
            let path = url.resolvingSymlinksInPath().path
            entries.append((String(path.dropFirst(rootPrefix.count)), url))
        }
        return
            entries
            .sorted {
                $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }
            .map(\.url)
    }

    /// Title for a picked item: last path component, minus a trailing `.zip`.
    /// A folder name is returned unchanged, so `Vol.3` stays `Vol.3`.
    public static func title(forSource url: URL) -> String {
        guard url.pathExtension.lowercased() == "zip" else { return url.lastPathComponent }
        return url.deletingPathExtension().lastPathComponent
    }
}
