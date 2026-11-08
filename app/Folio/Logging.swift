import OSLog

/// Loggers for the app. Use these instead of `print` so output is filterable,
/// privacy-aware, and visible in Console.app and `log stream`.
enum AppLog {
    static let subsystem = "io.lilikaine.github.folio"

    /// Catch-all logger. Add a category per subsystem as the app grows.
    static let general = Logger(subsystem: subsystem, category: "general")
}
