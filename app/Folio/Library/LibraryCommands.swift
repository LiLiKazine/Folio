#if os(macOS)
    import FolioCore
    import SwiftUI

    /// Mac menu commands for the Library: File → Import… (⌘I) and View → Sort By.
    ///
    /// Each command reaches the focused window through a focused value that
    /// `LibraryWindow` publishes with `.focusedSceneValue`:
    /// `FocusedValues.libraryImporterIsPresented` and `FocusedValues.libraryOrderChoice`.
    /// With no Library window focused the commands are disabled.
    struct LibraryCommands: Commands {
        @FocusedValue(\.libraryImporterIsPresented) private var importerIsPresented
        @FocusedValue(\.libraryOrderChoice) private var libraryOrderChoice

        var body: some Commands {
            CommandGroup(after: .newItem) {
                Button("Import…") {
                    importerIsPresented?.wrappedValue = true
                }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(importerIsPresented == nil)
            }
            CommandGroup(before: .toolbar) {
                Menu("Sort By") {
                    if let libraryOrderChoice {
                        LibraryOrderPickers(
                            order: libraryOrderChoice.order, choose: libraryOrderChoice.choose)
                    }
                }
                .disabled(libraryOrderChoice == nil)
            }
        }
    }

    /// Whether the focused window is showing its file picker for an Import.
    /// Setting it true asks for the picker through the window's `PresentationQueue`:
    /// it opens now, or after the dialogs asked for before it. Setting false does nothing.
    struct LibraryImporterIsPresentedKey: FocusedValueKey {
        typealias Value = Binding<Bool>
    }

    /// What View → Sort By needs from the focused window: the Library Order to tick,
    /// and the way to choose another.
    struct LibraryOrderChoice {
        let order: LibraryOrder
        let choose: (LibraryOrder) -> Void
    }

    struct LibraryOrderChoiceKey: FocusedValueKey {
        typealias Value = LibraryOrderChoice
    }

    extension FocusedValues {
        var libraryImporterIsPresented: Binding<Bool>? {
            get { self[LibraryImporterIsPresentedKey.self] }
            set { self[LibraryImporterIsPresentedKey.self] = newValue }
        }

        var libraryOrderChoice: LibraryOrderChoice? {
            get { self[LibraryOrderChoiceKey.self] }
            set { self[LibraryOrderChoiceKey.self] = newValue }
        }
    }
#endif
