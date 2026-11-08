import FolioCore
import Foundation

/// One dialog the Library screen can show.
enum Presentation: Equatable, Identifiable, Sendable {
    case notice(Notice)
    case importPicker
    case rename(Book)
    case deleteBook(Book)
    /// The Books selected when the user tapped Delete.
    case deleteSelection(Set<BookID>)

    var id: String {
        switch self {
        case .notice(let notice): "notice:\(notice.id.uuidString)"
        case .importPicker: "picker"
        case .rename(let book): "rename:\(book.id.rawValue.uuidString)"
        case .deleteBook(let book): "delete:\(book.id.rawValue.uuidString)"
        case .deleteSelection(let ids):
            "deleteSelection:" + ids.map(\.rawValue.uuidString).sorted().joined(separator: ",")
        }
    }
}

/// The single source of truth for which dialog the Library screen shows:
/// at most one is current, the rest wait in order.
struct PresentationQueue: Equatable, Sendable {
    private(set) var current: Presentation?
    private(set) var pending: [Presentation] = []

    init() {}

    /// Becomes current when idle, otherwise waits behind everything already
    /// queued. A request whose id is already current or pending is ignored:
    /// the same request twice is one request.
    mutating func enqueue(_ presentation: Presentation) {
        guard current?.id != presentation.id, !pending.contains(where: { $0.id == presentation.id })
        else { return }
        if current == nil {
            current = presentation
        } else {
            pending.append(presentation)
        }
    }

    /// Called when SwiftUI dismisses a Presentation (the name is SwiftUI's
    /// term for a dialog going away, not a Notice state). Promotes the next
    /// pending one; an id that is not current is ignored.
    mutating func dismissed(_ id: Presentation.ID) {
        guard current?.id == id else { return }
        current = pending.isEmpty ? nil : pending.removeFirst()
    }
}
