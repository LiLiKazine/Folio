import FolioCore
import Foundation
import Testing

@testable import Folio

@Suite("LibraryWindow")
struct LibraryWindowTests {
    private func book() -> Book {
        let id = BookID()
        return Book(
            id: id, title: "Vol 1", folderName: id.rawValue.uuidString,
            pages: [Page(fileName: "0001.png")], coverFileName: CoverImage.fileName,
            importedAt: .now, lastOpenedAt: nil, readingPosition: nil)
    }

    @Test("a Book is pushed once, however many times it is activated before it shows")
    func pushOnce() {
        let opened = book()
        var path: [Book] = []

        LibraryWindow.push(opened, onto: &path)
        LibraryWindow.push(opened, onto: &path)

        #expect(path == [opened])
    }

    @Test("a second, different Book is not pushed on top of the one being read")
    func oneBookAtATime() {
        let reading = book()
        var path = [reading]

        LibraryWindow.push(book(), onto: &path)

        #expect(path == [reading])
    }
}
