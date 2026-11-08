import FolioCore
import Testing

@testable import Folio

@Suite("Notice copy")
@MainActor struct NoticeTests {
    @Test("sourceUnavailable names the Source") func sourceUnavailable() {
        let notice = Notice(error: .sourceUnavailable(sourceName: "Vol 3"))
        #expect(notice.title == "Couldn't Import “Vol 3”")
        #expect(
            notice.message
                == "Folio couldn't open the folder or zip. Pick it again from the file picker.")
    }

    @Test("sourceNotDownloaded names the Source and reuses the Import reason text")
    func sourceNotDownloaded() {
        let notice = Notice(error: .sourceNotDownloaded(sourceName: "Vol 4"))
        #expect(notice.title == "Couldn't Import “Vol 4”")
        #expect(notice.message == "Not downloaded to this device")
    }

    @Test("emptyTitle") func emptyTitle() {
        let notice = Notice(error: .emptyTitle)
        #expect(notice.title == "Couldn't Rename")
        #expect(notice.message == "A Book needs a Title.")
    }

    @Test("notFound uses the operation") func notFound() {
        let notice = Notice(error: .notFound(.deleteBook))
        #expect(notice.title == "Couldn't Delete Book")
        #expect(notice.message == "It's no longer in the Library.")
    }

    @Test("invalidStatus") func invalidStatus() {
        let notice = Notice(error: .invalidStatus(.retryImport))
        #expect(notice.title == "Couldn't Retry Import")
        #expect(notice.message == "That Import has already moved on.")
    }

    @Test("storage error") func storage() {
        let notice = Notice(error: .storage(.rename))
        #expect(notice.title == "Couldn't Rename")
        #expect(
            notice.message
                == "Folio couldn't save the change. Try again; if it keeps happening, relaunch Folio."
        )
    }

    @Test("storage failed event") func storageFailed() {
        let notice = Notice(storageFailed: .updateLibrary)
        #expect(notice.title == "Couldn't Update the Library")
        #expect(
            notice.message
                == "Folio couldn't save the change. What you see may be out of date; relaunch Folio to refresh."
        )
    }

    @Test("open the Library") func openLibrary() {
        let expected = (
            title: "Couldn't Open the Library",
            message:
                "Folio couldn't open its Library. Relaunch Folio; if it keeps happening, free up storage."
        )
        for notice in [Notice(storageFailed: .openLibrary), Notice(error: .storage(.openLibrary))] {
            #expect(notice.title == expected.title)
            #expect(notice.message == expected.message)
        }
    }

    @Test("import failed keeps the existing reason text") func importFailed() {
        let notice = Notice(importFailed: "x.zip", reason: .noImagesFound)
        #expect(notice.title == "Couldn't Import “x.zip”")
        #expect(notice.message == "No images found")
    }

    @Test("every operation names itself in the title")
    func operationTitles() {
        for operation in LibraryOperation.allCases {
            #expect(Notice(error: .notFound(operation)).title == "Couldn't \(operation.rawValue)")
        }
    }
}
