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
            #expect(LibraryDropTarget.sources(in: [folder]) == [folder])
        }

        @Test("one zip is a Source, whatever the extension's case")
        func zipAccepted() {
            #expect(LibraryDropTarget.sources(in: [zip]) == [zip])
        }

        @Test("a .cbz is a Source, whatever the extension's case")
        func cbzAccepted() {
            let lower = URL(
                filePath: "/Users/reader/Downloads/Vol1.cbz", directoryHint: .notDirectory)
            let upper = URL(
                filePath: "/Users/reader/Downloads/Vol2.CBZ", directoryHint: .notDirectory)
            #expect(LibraryDropTarget.sources(in: [lower, upper]) == [lower, upper])
        }

        @Test("a URL that is neither a folder nor a zip is rejected")
        func otherFileRejected() {
            #expect(LibraryDropTarget.sources(in: [notASource]) == nil)
        }

        @Test("several folders and zips are Sources, in the drop's order")
        func severalAccepted() {
            #expect(LibraryDropTarget.sources(in: [zip, folder, zip]) == [zip, folder, zip])
        }

        @Test("a drop holding anything else is rejected whole")
        func anythingElseRejectsTheWholeDrop() {
            #expect(LibraryDropTarget.sources(in: [zip, notASource, folder]) == nil)
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

            #expect(LibraryDropTarget.sources(in: [url]) == [url])
        }

        @Test("a real file with no extension is rejected")
        func realFileWithoutExtensionRejected() throws {
            let url = FileManager.default.temporaryDirectory
                .appending(path: "LibraryDropTargetTests-\(UUID().uuidString)")
            try Data("not a Source".utf8).write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }

            #expect(LibraryDropTarget.sources(in: [url]) == nil)
        }

        @Test("an empty drop is rejected")
        func emptyRejected() {
            #expect(LibraryDropTarget.sources(in: []) == nil)
        }
    }
#endif
