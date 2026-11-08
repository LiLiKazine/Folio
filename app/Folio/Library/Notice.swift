import FolioCore
import Foundation

/// A message the Library shows the user about an action that could not be
/// completed: the title names what failed, the message what to do about it.
struct Notice: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let message: String

    private init(title: String, message: String) {
        id = UUID()
        self.title = title
        self.message = message
    }

    /// A Library operation the user started that threw.
    init(error: LibraryError) {
        switch error {
        case .sourceUnavailable(let sourceName):
            self.init(
                title: Self.importTitle(sourceName),
                message: String(
                    localized:
                        "Folio couldn't open the folder or zip. Pick it again from the file picker."
                ))
        case .sourceNotDownloaded(let sourceName):
            self.init(
                title: Self.importTitle(sourceName),
                message: ImportFailureReason.sourceNotDownloaded.localizedDescription)
        case .emptyTitle:
            self.init(
                title: Self.title(.rename), message: String(localized: "A Book needs a Title."))
        case .notFound(let operation):
            self.init(
                title: Self.title(operation),
                message: String(localized: "It's no longer in the Library."))
        case .invalidStatus(let operation):
            self.init(
                title: Self.title(operation),
                message: String(localized: "That Import has already moved on."))
        case .storage(.openLibrary):
            self.init(storageFailed: .openLibrary)
        case .storage(let operation):
            self.init(
                title: Self.title(operation),
                message: String(
                    localized:
                        "Folio couldn't save the change. Try again; if it keeps happening, relaunch Folio."
                ))
        }
    }

    /// A change the Library could not save or apply with no caller to tell
    /// (`LibraryStorageFailed`), or the Library failing to open at launch.
    init(storageFailed operation: LibraryOperation) {
        let message =
            operation == .openLibrary
            ? String(
                localized:
                    "Folio couldn't open its Library. Relaunch Folio; if it keeps happening, free up storage."
            )
            : String(
                localized:
                    "Folio couldn't save the change. What you see may be out of date; relaunch Folio to refresh."
            )
        self.init(title: Self.title(operation), message: message)
    }

    /// An Import that was created and then Failed.
    init(importFailed sourceName: String, reason: ImportFailureReason) {
        self.init(title: Self.importTitle(sourceName), message: reason.localizedDescription)
    }

    /// The system file picker failed before the user could pick a Source.
    static func filePickerFailed() -> Notice {
        Notice(
            title: title(.import),
            message: String(localized: "Folio couldn't open the file picker. Try again."))
    }

    /// True when `other` says the same thing, whatever its identity.
    func says(_ other: Notice) -> Bool {
        title == other.title && message == other.message
    }

    private static func title(_ operation: LibraryOperation) -> String {
        String(localized: "Couldn't \(operation.rawValue)")
    }

    private static func importTitle(_ sourceName: String) -> String {
        String(localized: "Couldn't Import “\(sourceName)”")
    }
}
