#if os(macOS)
    import Foundation
    import Testing

    @testable import Folio

    @Suite("Library drop target")
    struct LibraryDropTargetTests {
        private let folder = URL(
            filePath: "/Users/reader/Downloads/Sketches/", directoryHint: .isDirectory)
        private let zip = URL(
            filePath: "/Users/reader/Downloads/Sketches.ZIP", directoryHint: .notDirectory)
        private let notASource = URL(
            filePath: "/Users/reader/Downloads/page.png", directoryHint: .notDirectory)

        @Test("one folder is a Source")
        func folderAccepted() {
            #expect(LibraryDropTarget.source(in: [folder]) == folder)
        }

        @Test("one zip is a Source, whatever the extension's case")
        func zipAccepted() {
            #expect(LibraryDropTarget.source(in: [zip]) == zip)
        }

        @Test("a URL that is neither a folder nor a zip is rejected")
        func otherFileRejected() {
            #expect(LibraryDropTarget.source(in: [notASource]) == nil)
        }

        @Test("several URLs are rejected, even if each would be a Source")
        func severalRejected() {
            #expect(LibraryDropTarget.source(in: [folder, zip]) == nil)
        }

        @Test("a real folder without a trailing slash is a Source")
        func realFolderWithoutSlashAccepted() throws {
            let path = FileManager.default.temporaryDirectory
                .appending(path: "LibraryDropTargetTests-\(UUID().uuidString)").path
            try FileManager.default.createDirectory(
                atPath: path, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(atPath: path) }
            let url = URL(fileURLWithPath: path, isDirectory: false)
            #expect(!url.hasDirectoryPath)

            #expect(LibraryDropTarget.source(in: [url]) == url)
        }

        @Test("a real file with no extension is rejected")
        func realFileWithoutExtensionRejected() throws {
            let url = FileManager.default.temporaryDirectory
                .appending(path: "LibraryDropTargetTests-\(UUID().uuidString)")
            try Data("not a Source".utf8).write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }

            #expect(LibraryDropTarget.source(in: [url]) == nil)
        }

        @Test("an empty drop is rejected")
        func emptyRejected() {
            #expect(LibraryDropTarget.source(in: []) == nil)
        }
    }
#endif
