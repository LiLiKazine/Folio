import FolioCore
import Foundation
import Testing

@testable import Folio

@Suite("Library Order menu")
@MainActor
struct LibraryOrderMenuTests {
    @Test("every Sort and every Direction has its own label")
    func labels() {
        #expect(
            LibraryOrder.Sort.allCases.map { String(localized: $0.label) } == [
                "Recent", "Title", "Date Imported",
            ])
        #expect(
            LibraryOrder.Direction.allCases.map { String(localized: $0.label) } == [
                "Ascending", "Descending",
            ])
    }

    @Test("picking a Sort keeps the Direction, and picking a Direction keeps the Sort")
    func pickingKeepsTheOtherHalf() {
        let order = LibraryOrder(sort: .recent, direction: .ascending)
        var chosen: [LibraryOrder] = []

        let sort = LibraryOrderPickers.sortBinding(order: order) { chosen.append($0) }
        let direction = LibraryOrderPickers.directionBinding(order: order) { chosen.append($0) }
        #expect(sort.wrappedValue == .recent)
        #expect(direction.wrappedValue == .ascending)

        sort.wrappedValue = .title
        direction.wrappedValue = .descending

        #expect(
            chosen == [
                LibraryOrder(sort: .title, direction: .ascending),
                LibraryOrder(sort: .recent, direction: .descending),
            ])
    }
}
