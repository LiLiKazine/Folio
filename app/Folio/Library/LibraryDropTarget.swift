#if os(macOS)
    import SwiftUI

    /// Lets the user drop one folder or zip onto the Library to Import it.
    ///
    /// Anything else (several URLs, or one that is neither) is rejected and the
    /// drop is refused. While a drag hovers over the Library, a subtle accent-colour
    /// outline shows where it will land.
    struct LibraryDropTarget: ViewModifier {
        /// Called with the Source to Import when a drop is accepted.
        let onImport: (URL) -> Void

        @State private var isTargeted = false

        func body(content: Content) -> some View {
            content
                .dropDestination(for: URL.self) { urls, _ in
                    guard let source = Self.source(in: urls) else { return false }
                    onImport(source)
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

        /// The Source in a drop, or nil when the drop is not exactly one folder or zip.
        nonisolated static func source(in urls: [URL]) -> URL? {
            guard urls.count == 1, let url = urls.first else { return nil }
            if isFolder(url) || url.pathExtension.lowercased() == "zip" {
                return url
            }
            return nil
        }

        /// A dropped folder's URL need not end in "/", so ask the file system too.
        nonisolated private static func isFolder(_ url: URL) -> Bool {
            url.hasDirectoryPath
                || (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
    }

    extension View {
        /// Accepts a dropped folder or zip as a Source to Import.
        func libraryDropTarget(onImport: @escaping (URL) -> Void) -> some View {
            modifier(LibraryDropTarget(onImport: onImport))
        }
    }
#endif
