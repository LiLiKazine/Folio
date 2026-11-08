import FolioCore
import Foundation

/// A message the Library shows the user about an action that could not be
/// completed: the title names what failed, the message what to do about it.
struct Notice: Identifiable, Equatable, Sendable {
    /// How the Notice is shown, following the Human Interface Guidelines.
    enum Kind: Sendable, Equatable {
        /// Answers an action the user just took, so it is shown as a dialog.
        case dialog
        /// Reports a failure with no action of the user's behind it (a
        /// `LibraryStorageFailed` event, a launch or reload failure), so it is
        /// shown as a status line rather than interrupting the user.
        case status
    }

    let id: UUID
    let kind: Kind
    let title: String
    let message: String

    private init(kind: Kind, title: String, message: String) {
        id = UUID()
        self.kind = kind
        self.title = title
        self.message = message
    }

    /// A dialog Notice; every initializer but `init(storageFailed:)` makes one.
    private init(title: String, message: String) {
        self.init(kind: .dialog, title: title, message: message)
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
            self.init(
                title: Self.title(.openLibrary), message: Self.storageFailedMessage(.openLibrary))
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
        self.init(
            kind: .status, title: Self.title(operation),
            message: Self.storageFailedMessage(operation))
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

    /// True when `other` says the same thing in the same way, whatever its identity.
    func says(_ other: Notice) -> Bool {
        kind == other.kind && title == other.title && message == other.message
    }

    private static func title(_ operation: LibraryOperation) -> String {
        String(localized: "Couldn't \(operation.rawValue)")
    }

    private static func storageFailedMessage(_ operation: LibraryOperation) -> String {
        operation == .openLibrary
            ? String(
                localized:
                    "Folio couldn't open its Library. Relaunch Folio; if it keeps happening, free up storage."
            )
            : String(
                localized:
                    "Folio couldn't save the change. What you see may be out of date; relaunch Folio to refresh."
            )
    }

    private static func importTitle(_ sourceName: String) -> String {
        String(localized: "Couldn't Import “\(sourceName)”")
    }
}
