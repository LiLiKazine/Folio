import FolioCore
import SwiftUI

/// The Library screen: every Book and every Import that has not produced one,
/// in an adaptive grid, with Import, rename, and delete.
struct LibraryView: View {
    let model: LibraryModel
    /// Asks the window to show a dialog; the window owns every dialog.
    let request: (Presentation) -> Void
    /// Asks the window to open a Book.
    let open: (Book) -> Void

    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
        /// The Book a single click selected; the target of the Delete key.
        @State private var selection: BookID?
        @FocusState private var gridIsFocused: Bool
    #else
        /// Select mode is offered only in the regular width of an iPad.
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        @State private var isSelecting = false
        @State private var selectedBookIDs: Set<BookID> = []
    #endif

    init(
        model: LibraryModel, request: @escaping (Presentation) -> Void,
        open: @escaping (Book) -> Void
    ) {
        self.model = model
        self.request = request
        self.open = open
    }

    var body: some View {
        content
            .navigationTitle("Library")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    #if os(macOS)
                        Button("Import…", systemImage: "plus") { request(.importPicker) }
                            .help("Import a folder or zip")
                    #else
                        Button("Import", systemImage: "plus") { request(.importPicker) }
                    #endif
                }
                ToolbarItem(placement: .automatic) { sortMenu }
                #if os(iOS)
                    if horizontalSizeClass == .regular {
                        ToolbarItem(placement: .topBarTrailing) {
                            if isSelecting {
                                Button("Done") { endSelecting() }
                            } else {
                                Button("Select") { isSelecting = true }
                                    .disabled(!hasBooks)
                            }
                        }
                    }
                #endif
            }
            #if os(macOS)
                .onChange(of: model.items) {
                    if selectedBook == nil { selection = nil }
                }
            #else
                .safeAreaInset(edge: .bottom) {
                    if isSelecting {
                        LibrarySelectionBar(count: selectedBookIDs.count) {
                            request(.deleteSelection(selectedBookIDs))
                        }
                    }
                }
                .onChange(of: model.items) { pruneSelection() }
                .onChange(of: horizontalSizeClass) {
                    if horizontalSizeClass != .regular { endSelecting() }
                }
            #endif
            .onAppear {
                Task { await model.reload() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await model.reload() }
                }
            }
    }

    @ViewBuilder private var content: some View {
        if model.isLoaded && model.items.isEmpty {
            LibraryEmptyView { request(.importPicker) }
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 12)],
                    spacing: 16
                ) {
                    ForEach(model.items) { item in
                        card(for: item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            #if os(macOS)
                .contentShape(.rect)
                .onTapGesture { selection = nil }
                .focusable()
                .focusEffectDisabled()
                .focused($gridIsFocused)
                .onDeleteCommand(perform: deleteSelectedBook)
                .onKeyPress(.return) {
                    guard let book = selectedBook else { return .ignored }
                    open(book)
                    return .handled
                }
            #endif
        }
    }

    /// Chooses the Library Order. The ticks move once the Library has saved the choice;
    /// a failed save shows a Notice and leaves the grid and the ticks as they were.
    private var sortMenu: some View {
        Menu("Sort", systemImage: "arrow.up.arrow.down") {
            LibraryOrderPickers(order: model.libraryOrder) { order in
                Task { await model.chooseLibraryOrder(order) }
            }
        }
        #if os(macOS)
            .help("Sort")
        #endif
        .disabled(!hasBooks)
    }

    private var hasBooks: Bool {
        model.items.contains { if case .book = $0 { true } else { false } }
    }

    #if os(macOS)
        /// Presents the delete confirmation for the selected Book; nil with no
        /// selection, which leaves the Delete key and Edit → Delete disabled.
        private var deleteSelectedBook: (() -> Void)? {
            guard let book = selectedBook else { return nil }
            return { request(.deleteBook(book)) }
        }

        private var selectedBook: Book? {
            guard let selection else { return nil }
            for case .book(let book) in model.items where book.id == selection {
                return book
            }
            return nil
        }
    #else
        /// Leaves Select mode; the selection does not outlive it.
        private func endSelecting() {
            isSelecting = false
            selectedBookIDs = []
        }

        /// Drops selected Books that have left the Library; when that empties the
        /// selection, which is what a confirmed delete does, Select mode ends.
        private func pruneSelection() {
            var present = Set<BookID>()
            for case .book(let book) in model.items { present.insert(book.id) }
            let hadSelection = !selectedBookIDs.isEmpty
            selectedBookIDs.formIntersection(present)
            if !hasBooks || (hadSelection && selectedBookIDs.isEmpty) { endSelecting() }
        }
    #endif

    /// True while the iPad selects Books; context menus and Import cards step aside.
    private var isSelectingBooks: Bool {
        #if os(iOS)
            isSelecting
        #else
            false
        #endif
    }

    @ViewBuilder private func card(for item: FolioCore.LibraryItem) -> some View {
        switch item {
        case .book(let book):
            bookCard(for: book)
                .contextMenu {
                    if !isSelectingBooks {
                        Button("Rename…", systemImage: "pencil") { request(.rename(book)) }
                        Button("Delete Book", systemImage: "trash", role: .destructive) {
                            request(.deleteBook(book))
                        }
                    }
                }
        case .importRecord(let record):
            ImportCard(record: record, liveProgress: model.liveProgress[record.id]) {
                Task { await model.retryImport(record.id) }
            }
            .disabled(isSelectingBooks)
            .opacity(isSelectingBooks ? 0.4 : 1)
            .contextMenu {
                if !isSelectingBooks {
                    importMenu(for: record)
                }
            }
        }
    }

    @ViewBuilder private func importMenu(for record: FolioCore.Import) -> some View {
        switch record.status {
        case .inProgress, .queued:
            Button("Cancel Import", systemImage: "xmark") {
                Task { await model.cancelImport(record.id) }
            }
        case .failed:
            Button("Retry", systemImage: "arrow.clockwise") {
                Task { await model.retryImport(record.id) }
            }
            Button("Remove", systemImage: "trash", role: .destructive) {
                Task { await model.removeImport(record.id) }
            }
        case .completed:
            EmptyView()
        }
    }

    #if os(macOS)
        /// Single click selects, double click opens, per the Mac HIG.
        private func bookCard(for book: Book) -> some View {
            BookCard(
                book: book, coverURL: model.coverURL(for: book), isSelected: selection == book.id
            )
            .onTapGesture(count: 2) {
                open(book)
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    selection = book.id
                    gridIsFocused = true
                }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                open(book)
            }
        }
    #else
        /// A tap opens, or while selecting, adds the Book to or removes it from the selection.
        private func bookCard(for book: Book) -> some View {
            let isChecked = isSelecting && selectedBookIDs.contains(book.id)
            return Button {
                if isSelecting {
                    if isChecked {
                        selectedBookIDs.remove(book.id)
                    } else {
                        selectedBookIDs.insert(book.id)
                    }
                } else {
                    open(book)
                }
            } label: {
                BookCard(
                    book: book, coverURL: model.coverURL(for: book), isSelected: isChecked,
                    showsCheckmark: isChecked
                )
            }
            .buttonStyle(.plain)
        }
    #endif
}
