import FolioCore
import SwiftUI

@main
struct FolioApp: App {
    /// Nil when Folio's storage could not be set up at launch.
    @State private var model: LibraryModel?
    /// Runs `LibraryModel.start()` for the whole process. It is owned by the App, not
    /// a window: closing the last window on macOS (Cmd-W) would cancel a window's
    /// `.task` while the app keeps running, and `Library.start()` must not run twice
    /// because it clears staging. Never cancelled.
    @State private var eventLoop: Task<Void, Never>?

    init() {
        // Also proves FolioCore is linked into the app target: remove the
        // package dependency and this file stops compiling.
        AppLog.general.info("Folio launched \(BookID().rawValue.uuidString, privacy: .public)")
        _model = State(initialValue: Self.makeModel())
    }

    var body: some Scene {
        WindowGroup {
            if let model {
                NavigationStack {
                    LibraryView(model: model)
                }
                .onAppear {
                    if eventLoop == nil {
                        eventLoop = Task { await model.start() }
                    }
                }
            } else {
                Text("Folio couldn't open its Library.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        #if os(macOS)
            .commands { LibraryCommands() }
        #endif
    }

    private static func makeModel() -> LibraryModel? {
        do {
            let booksDirectory = try LibraryStorage.booksDirectory()
            let container = try LibraryStorage.makeContainer()
            let library = Library(
                books: SwiftDataBookRepository(modelContainer: container),
                imports: SwiftDataImportRepository(modelContainer: container),
                pipeline: ImportPipeline(booksDirectory: booksDirectory),
                sourceAccess: FileSourceAccess()
            )
            return LibraryModel(library: library, booksDirectory: booksDirectory)
        } catch {
            AppLog.general.error(
                "Could not set up the Library: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
