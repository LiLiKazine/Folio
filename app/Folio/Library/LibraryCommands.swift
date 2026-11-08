#if os(macOS)
    import SwiftUI

    /// Mac menu commands for the Library: File → Import… (⌘I).
    ///
    /// The command reaches the focused window's Library screen through
    /// `FocusedValues.libraryImporterIsPresented`, which `LibraryView` publishes with
    /// `.focusedSceneValue`. With no Library window focused the command is disabled.
    struct LibraryCommands: Commands {
        @FocusedValue(\.libraryImporterIsPresented) private var importerIsPresented

        var body: some Commands {
            CommandGroup(after: .newItem) {
                Button("Import…") {
                    importerIsPresented?.wrappedValue = true
                }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(importerIsPresented == nil)
            }
        }
    }

    /// Whether the focused Library screen is showing its file picker for an Import.
    struct LibraryImporterIsPresentedKey: FocusedValueKey {
        typealias Value = Binding<Bool>
    }

    extension FocusedValues {
        var libraryImporterIsPresented: Binding<Bool>? {
            get { self[LibraryImporterIsPresentedKey.self] }
            set { self[LibraryImporterIsPresentedKey.self] = newValue }
        }
    }
#endif
