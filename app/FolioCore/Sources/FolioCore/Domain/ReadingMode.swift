/// How a Book's Pages are laid out while reading. Each Book remembers its own; a Book
/// that has none reads Page by Page.
public enum ReadingMode: String, Codable, Sendable, CaseIterable {
    /// One Page at a time, turned by swiping.
    case pageByPage
    /// Every Page stacked into one strip, scrolled top to bottom.
    case vertical
}
