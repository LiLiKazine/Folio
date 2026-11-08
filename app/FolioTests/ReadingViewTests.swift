import FolioCore
import Foundation
import Testing

@testable import Folio

@Suite("ReadingView")
struct ReadingViewTests {
    private func book(pageCount: Int, readingPosition: Int?) -> Book {
        let id = BookID()
        return Book(
            id: id, title: "Vol 1", folderName: id.rawValue.uuidString,
            pages: (1...pageCount).map { Page(fileName: String(format: "%04d.png", $0)) },
            coverFileName: CoverImage.fileName, importedAt: .now, lastOpenedAt: nil,
            readingPosition: readingPosition)
    }

    @Test(
        "startIndex is the Reading Position, the first Page when none, and the last Page when past the end",
        arguments: [
            (pageCount: 180, position: Int?.none, expected: 0),
            (pageCount: 180, position: 73, expected: 73),
            (pageCount: 180, position: 179, expected: 179),
            (pageCount: 180, position: 200, expected: 179),
            (pageCount: 1, position: 0, expected: 0),
            (pageCount: 1, position: 5, expected: 0),
            (pageCount: 5, position: -3, expected: 0),
        ])
    func startIndex(pageCount: Int, position: Int?, expected: Int) {
        let book = book(pageCount: pageCount, readingPosition: position)

        #expect(ReadingView.startIndex(for: book) == expected)
    }

    @Test(
        "decodeSize rounds the window up to a multiple of 256 pixels, so a resize rebuilds the cache in steps",
        arguments: [
            (windowPixels: 0, expected: 256),
            (windowPixels: 1, expected: 256),
            (windowPixels: 256, expected: 256),
            (windowPixels: 257, expected: 512),
            (windowPixels: 2622, expected: 2816),
        ])
    func decodeSize(windowPixels: Int, expected: Int) {
        #expect(ReadingView.decodeSize(forWindowPixels: windowPixels) == expected)
    }
}
