import FolioCore
import Foundation
import SwiftUI
import Testing

@testable import Folio

@Suite("ReadingView")
struct ReadingViewTests {
    private func book(
        pageCount: Int, readingPosition: Int?, readingMode: ReadingMode = .pageByPage
    ) -> Book {
        let id = BookID()
        return Book(
            id: id, title: "Vol 1", folderName: id.rawValue.uuidString,
            pages: (1...pageCount).map { Page(fileName: String(format: "%04d.png", $0)) },
            coverFileName: CoverImage.fileName, importedAt: .now, lastOpenedAt: nil,
            readingPosition: readingPosition, readingMode: readingMode)
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

    @Test("startMode is the Book's own Reading Mode", arguments: ReadingMode.allCases)
    func startMode(mode: ReadingMode) {
        let book = book(pageCount: 3, readingPosition: 1, readingMode: mode)

        #expect(ReadingView.startMode(for: book) == mode)
    }

    @Test(
        "The strip's scroll is measured from the top of the content, under any inset the scroll view adds"
    )
    func stripScrollMeasuresFromTheContentTop() {
        // Under an inset the content offset sits before zero at rest at the top
        // ("may extend before zero ... when the content insets ... are non-zero").
        let atRest = ScrollGeometry(
            contentOffset: CGPoint(x: 0, y: -50), contentSize: CGSize(width: 390, height: 3000),
            contentInsets: EdgeInsets(top: 50, leading: 0, bottom: 0, trailing: 0),
            containerSize: CGSize(width: 390, height: 800))
        let scrolled = ScrollGeometry(
            contentOffset: CGPoint(x: 0, y: 1150), contentSize: CGSize(width: 390, height: 3000),
            contentInsets: EdgeInsets(top: 50, leading: 0, bottom: 0, trailing: 0),
            containerSize: CGSize(width: 390, height: 800))

        #expect(StripScroll(atRest) == StripScroll(offset: 0, viewportHeight: 800))
        #expect(StripScroll(scrolled) == StripScroll(offset: 1200, viewportHeight: 800))
    }

    @Test("The strip's sideways scroll is measured from its left edge, under any leading inset")
    func stripScrollMeasuresFromTheLeftEdge() {
        let panned = ScrollGeometry(
            contentOffset: CGPoint(x: 280, y: 0), contentSize: CGSize(width: 1170, height: 3000),
            contentInsets: EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 0),
            containerSize: CGSize(width: 390, height: 800))

        #expect(StripScroll(panned) == StripScroll(offset: 0, viewportHeight: 800, offsetX: 300))
    }

    @Test(
        "A pinch grows the strip about the top centre of the screen: at fit and at the top that is the strip's top centre; zoomed, scrolled and panned it is the point under the screen's top centre; a strip with no size gives the top centre"
    )
    func pinchAnchorIsTheScreensTopCentre() {
        let atFit = VerticalStripView.pinchAnchor(
            scroll: StripScroll(offset: 0, viewportHeight: 800), viewportWidth: 390,
            contentWidth: 390, contentHeight: 3000)
        #expect(atFit == UnitPoint(x: 0.5, y: 0))

        let zoomed = VerticalStripView.pinchAnchor(
            scroll: StripScroll(offset: 3000, viewportHeight: 800, offsetX: 200),
            viewportWidth: 400, contentWidth: 1000, contentHeight: 12000)
        #expect(zoomed == UnitPoint(x: 0.4, y: 0.25))

        let empty = VerticalStripView.pinchAnchor(
            scroll: StripScroll(offset: 0, viewportHeight: 800), viewportWidth: 390,
            contentWidth: 390, contentHeight: 0)
        #expect(empty == .top)
    }

    @Test(
        "Only the reader moves the strip in interacting and decelerating; idle, tracking (a finger down that has not moved) and animating are not the reader",
        arguments: [
            (phase: ScrollPhase.idle, expected: false),
            (phase: ScrollPhase.tracking, expected: false),
            (phase: ScrollPhase.interacting, expected: true),
            (phase: ScrollPhase.decelerating, expected: true),
            (phase: ScrollPhase.animating, expected: false),
        ])
    func readerScrolling(phase: ScrollPhase, expected: Bool) {
        #expect(VerticalStripView.isReaderScrolling(phase) == expected)
    }
}
