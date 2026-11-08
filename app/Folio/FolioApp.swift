import FolioCore
import SwiftUI

@main
struct FolioApp: App {
    /// Nil when Folio's storage could not be set up at launch.
    @State private var model: LibraryModel?
    /// `LibraryModel.start()` must run once for the app's lifetime, not once per window.
    @State private var hasStarted = false

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
                .task {
                    guard !hasStarted else { return }
                    hasStarted = true
                    await model.start()
                }
            } else {
                Text("Folio couldn't open its Library.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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
