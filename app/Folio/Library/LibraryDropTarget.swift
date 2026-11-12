#if os(macOS)
    import FolioCore
    import SwiftUI

    /// Lets the user drop several folders and zips onto the Library to Import each.
    ///
    /// A drop that is empty, or holds anything that is neither a folder nor a zip, is
    /// rejected whole and the drop is refused; nothing is Imported. While a drag hovers
    /// over the Library, a subtle accent-colour outline shows where it will land.
    struct LibraryDropTarget: ViewModifier {
        /// Called with the Sources to Import, in the drop's order, when a drop is accepted.
        let onImport: ([URL]) -> Void

        @State private var isTargeted = false

        func body(content: Content) -> some View {
            content
                .dropDestination(for: URL.self) { urls, _ in
                    guard let sources = Self.sources(in: urls) else { return false }
                    onImport(sources)
                    return true
                } isTargeted: {
                    isTargeted = $0
                }
                .overlay {
                    if isTargeted {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                            .background(
                                Color.accentColor.opacity(0.06), in: .rect(cornerRadius: 10)
                            )
                            .padding(6)
                            .allowsHitTesting(false)
                    }
                }
        }

        /// The Sources in a drop, in the drop's order, or nil when the drop is empty or
        /// holds anything that is not a folder or zip.
        nonisolated static func sources(in urls: [URL]) -> [URL]? {
            guard !urls.isEmpty else { return nil }
            let isEverySource = urls.allSatisfy {
                isFolder($0) || SourceScanner.isZip($0)
            }
            return isEverySource ? urls : nil
        }

        /// A dropped folder's URL need not end in "/", so ask the file system too.
        nonisolated private static func isFolder(_ url: URL) -> Bool {
            // Ignored: a URL whose kind cannot be read is treated as not a folder, and
            // the drop is refused like any other unsupported item, visibly springing back.
            url.hasDirectoryPath
                || (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
    }

    extension View {
        /// Accepts dropped folders and zips as Sources to Import, one Import each.
        func libraryDropTarget(onImport: @escaping ([URL]) -> Void) -> some View {
            modifier(LibraryDropTarget(onImport: onImport))
        }
    }
#endif
