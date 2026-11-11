import FolioCore
import Foundation
import SwiftData

/// Stored form of the `LibraryOrder`. There is at most one row. Lives only inside
/// `SwiftDataLibraryOrderRepository`; callers see `LibraryOrder` values.
@Model
final class LibraryOrderModel {
    /// `LibraryOrder.Sort`'s raw value.
    var sort: String
    /// `LibraryOrder.Direction`'s raw value.
    var direction: String

    init(_ order: LibraryOrder) {
        sort = order.sort.rawValue
        direction = order.direction.rawValue
    }

    /// Overwrites both stored fields with `order`'s values.
    func apply(_ order: LibraryOrder) {
        sort = order.sort.rawValue
        direction = order.direction.rawValue
    }

    /// `LibraryOrder.initial` when either raw value names no case.
    var libraryOrder: LibraryOrder {
        guard
            let sort = LibraryOrder.Sort(rawValue: sort),
            let direction = LibraryOrder.Direction(rawValue: direction)
        else { return .initial }
        return LibraryOrder(sort: sort, direction: direction)
    }
}
