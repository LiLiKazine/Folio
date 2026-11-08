import FolioCore
import Foundation
import Testing

@testable import Folio

@Suite("Presentation queue")
struct PresentationQueueTests {
    private func makeBook(title: String = "Book") -> Book {
        Book(
            id: BookID(), title: title, folderName: "folder", pages: [],
            coverFileName: "cover.jpg", importedAt: Date(timeIntervalSince1970: 0),
            lastOpenedAt: nil, readingPosition: nil)
    }

    @Test("enqueue while idle presents at once")
    func enqueueWhenIdlePresents() {
        var queue = PresentationQueue()
        queue.enqueue(.importPicker)
        #expect(queue.current == .importPicker)
        #expect(queue.pending.isEmpty)
    }

    @Test("enqueue while busy queues in order")
    func enqueueWhenBusyQueuesInOrder() {
        var queue = PresentationQueue()
        let book = makeBook()
        queue.enqueue(.importPicker)
        queue.enqueue(.rename(book))
        queue.enqueue(.deleteBook(book))
        #expect(queue.current == .importPicker)
        #expect(queue.pending == [.rename(book), .deleteBook(book)])
    }

    @Test("dismissed promotes the next pending presentation")
    func dismissedPromotesNext() {
        var queue = PresentationQueue()
        let book = makeBook()
        queue.enqueue(.importPicker)
        queue.enqueue(.rename(book))
        queue.dismissed(Presentation.importPicker.id)
        #expect(queue.current == .rename(book))
        #expect(queue.pending.isEmpty)
    }

    @Test("a stale id is ignored")
    func staleDismissedIgnored() {
        var queue = PresentationQueue()
        let book = makeBook()
        queue.enqueue(.importPicker)
        queue.enqueue(.rename(book))
        queue.dismissed(Presentation.rename(book).id)
        #expect(queue.current == .importPicker)
        #expect(queue.pending == [.rename(book)])
    }

    @Test("a mixed sequence is presented in order")
    func mixedSequenceInOrder() {
        var queue = PresentationQueue()
        let first = Notice.filePickerFailed()
        let second = Notice.filePickerFailed()
        let book = makeBook()
        let sequence: [Presentation] = [
            .notice(first), .importPicker, .rename(book), .notice(second),
        ]
        sequence.forEach { queue.enqueue($0) }

        var shown: [Presentation] = []
        while let current = queue.current {
            shown.append(current)
            queue.dismissed(current.id)
        }
        #expect(shown == sequence)
        #expect(queue.pending.isEmpty)
    }

    @Test("dismissed with nothing pending leaves the queue idle")
    func dismissedWithEmptyPendingLeavesIdle() {
        var queue = PresentationQueue()
        queue.enqueue(.importPicker)
        queue.dismissed(Presentation.importPicker.id)
        #expect(queue.current == nil)
        #expect(queue.pending.isEmpty)
    }

    @Test("a multi-delete id ignores selection order and tells different selections apart")
    func deleteSelectionIDIsStable() {
        let first = BookID()
        let second = BookID()
        let third = BookID()
        let forward = Presentation.deleteSelection([first, second, third])
        let backward = Presentation.deleteSelection(Set([third, second, first]))
        #expect(forward.id == backward.id)
        #expect(forward.id != Presentation.deleteSelection([first, second]).id)
        #expect(forward.id != Presentation.deleteSelection([first, second, BookID()]).id)
    }

    @Test("asking for the picker while it is current is one request")
    func duplicateCurrentIgnored() {
        var queue = PresentationQueue()
        queue.enqueue(.importPicker)
        queue.enqueue(.importPicker)
        #expect(queue.current == .importPicker)
        #expect(queue.pending.isEmpty)
    }

    @Test("asking to rename the same Book while it waits is one request")
    func duplicatePendingIgnored() {
        var queue = PresentationQueue()
        let book = makeBook()
        queue.enqueue(.importPicker)
        queue.enqueue(.rename(book))
        queue.enqueue(.rename(book))
        #expect(queue.pending == [.rename(book)])
    }

    @Test("renames of different Books are different requests")
    func differentBooksNotConfused() {
        var queue = PresentationQueue()
        let first = makeBook(title: "First")
        let second = makeBook(title: "Second")
        queue.enqueue(.rename(first))
        queue.enqueue(.rename(second))
        #expect(queue.current == .rename(first))
        #expect(queue.pending == [.rename(second)])
    }
}
