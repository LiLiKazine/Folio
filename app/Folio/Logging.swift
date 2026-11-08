import OSLog

/// Loggers for the app. Use these instead of `print` so output is filterable,
/// privacy-aware, and visible in Console.app and `log stream`.
enum AppLog {
    static let subsystem = "io.lilikaine.github.folio"

    /// Catch-all logger. Add a category per subsystem as the app grows.
    static let general = Logger(subsystem: subsystem, category: "general")

    /// SwiftData store and the Books directory.
    static let persistence = Logger(subsystem: subsystem, category: "persistence")

    /// The Library screen's model and the operations it sends to the Library.
    static let library = Logger(subsystem: subsystem, category: "library")

    /// The reading screen and the Page decoder.
    static let reading = Logger(subsystem: subsystem, category: "reading")
}
