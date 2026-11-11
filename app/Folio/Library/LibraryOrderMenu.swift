import FolioCore
import SwiftUI

extension LibraryOrder.Sort {
    /// The Sort as the Sort menu shows it.
    var label: LocalizedStringResource {
        switch self {
        case .recent: "Recent"
        case .title: "Title"
        case .dateImported: "Date Imported"
        }
    }
}

extension LibraryOrder.Direction {
    /// The Direction as the Sort menu shows it.
    var label: LocalizedStringResource {
        switch self {
        case .ascending: "Ascending"
        case .descending: "Descending"
        }
    }
}

/// The two groups of the Sort menu, the Sorts then the Directions, separated by a
/// divider and with no headings; the Library Order in force is ticked. Used by the
/// toolbar menu and by the Mac's View → Sort By.
///
/// The ticks follow `order`, so they move only once the Library has saved a choice.
/// Each pick passes `choose` the Library Order with the other half unchanged: picking
/// a Sort keeps the Direction.
struct LibraryOrderPickers: View {
    let order: LibraryOrder
    let choose: (LibraryOrder) -> Void

    var body: some View {
        // The labels are hidden: the menu has no headings. SwiftUI still uses them for
        // accessibility.
        Picker("Sort", selection: Self.sortBinding(order: order, choose: choose)) {
            ForEach(LibraryOrder.Sort.allCases, id: \.self) { sort in
                Text(sort.label).tag(sort)
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
        Divider()
        Picker("Direction", selection: Self.directionBinding(order: order, choose: choose)) {
            ForEach(LibraryOrder.Direction.allCases, id: \.self) { direction in
                Text(direction.label).tag(direction)
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }

    /// Reads the Sort of `order`; a pick chooses that Sort with the Direction of `order`.
    static func sortBinding(
        order: LibraryOrder, choose: @escaping (LibraryOrder) -> Void
    ) -> Binding<LibraryOrder.Sort> {
        Binding(
            get: { order.sort },
            set: { choose(LibraryOrder(sort: $0, direction: order.direction)) }
        )
    }

    /// Reads the Direction of `order`; a pick chooses that Direction with the Sort of
    /// `order`.
    static func directionBinding(
        order: LibraryOrder, choose: @escaping (LibraryOrder) -> Void
    ) -> Binding<LibraryOrder.Direction> {
        Binding(
            get: { order.direction },
            set: { choose(LibraryOrder(sort: order.sort, direction: $0)) }
        )
    }
}
