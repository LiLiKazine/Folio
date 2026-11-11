import Foundation

/// The order Books appear in the Library: a Sort and a Direction.
public struct LibraryOrder: Equatable, Hashable, Sendable, Codable {
    /// What Books are ordered by.
    public enum Sort: String, Codable, Sendable, CaseIterable {
        case recent, title, dateImported
    }

    /// Which way a Sort runs.
    public enum Direction: String, Codable, Sendable, CaseIterable {
        case ascending, descending
    }

    public var sort: Sort
    public var direction: Direction

    public init(sort: Sort, direction: Direction) {
        self.sort = sort
        self.direction = direction
    }

    /// Recent, Descending.
    public static let initial = LibraryOrder(sort: .recent, direction: .descending)
}

extension Array where Element == Book {
    /// The Books in the Library Order. Ascending is a total order per Sort, with ties broken by
    /// Date Imported and then by the Book's identifier; Descending is exactly Ascending reversed.
    public func ordered(by order: LibraryOrder) -> [Book] {
        let ascending = sorted { $0.isBefore($1, by: order.sort) }
        switch order.direction {
        case .ascending: return ascending
        case .descending: return ascending.reversed()
        }
    }
}

extension Book {
    /// Whether this Book comes before `other` when the Sort runs Ascending.
    fileprivate func isBefore(_ other: Book, by sort: LibraryOrder.Sort) -> Bool {
        switch sort {
        case .recent:
            let mine = lastOpenedAt ?? importedAt
            let theirs = other.lastOpenedAt ?? other.importedAt
            if mine != theirs { return mine < theirs }
            if importedAt != other.importedAt { return importedAt < other.importedAt }
        case .title:
            let comparison = title.localizedStandardCompare(other.title)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            if importedAt != other.importedAt { return importedAt < other.importedAt }
        case .dateImported:
            if importedAt != other.importedAt { return importedAt < other.importedAt }
        }
        return id.rawValue.uuidString < other.id.rawValue.uuidString
    }
}
