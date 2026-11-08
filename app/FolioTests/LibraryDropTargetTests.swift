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

        @Test("an empty drop is rejected")
        func emptyRejected() {
            #expect(LibraryDropTarget.source(in: []) == nil)
        }
    }
#endif
