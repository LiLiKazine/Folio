import FolioCore
import SwiftUI
import UniformTypeIdentifiers

/// The Library screen: every Book and every Import that has not produced one,
/// in an adaptive grid, with Import, rename, and delete.
struct LibraryView: View {
    let model: LibraryModel

    @Environment(\.scenePhase) private var scenePhase
    @State private var isImporting = false
    @State private var bookToRename: Book?
    @State private var renameTitle = ""
    @State private var bookToDelete: Book?
    /// The Notice the alert shows; see `showPresentedNotice()`.
    @State private var shownNotice: Notice?
    #if os(macOS)
        /// The Book a single click selected; the target of the Delete key.
        @State private var selection: BookID?
        @FocusState private var gridIsFocused: Bool
    #else
        /// Select mode is offered only in the regular width of an iPad.
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        @State private var isSelecting = false
        @State private var selectedBookIDs: Set<BookID> = []
        @State private var isConfirmingDeleteSelection = false
    #endif

    init(model: LibraryModel) {
        self.model = model
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
                        Button("Import…", systemImage: "plus") { isImporting = true }
                            .help("Import a folder or zip")
                    #else
                        Button("Import", systemImage: "plus") { isImporting = true }
                    #endif
                }
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
                .focusedSceneValue(\.libraryImporterIsPresented, $isImporting)
                .libraryDropTarget(onImport: importSource)
                .onChange(of: model.items) {
                    if selectedBook == nil { selection = nil }
                }
            #else
                .safeAreaInset(edge: .bottom) {
                    if isSelecting {
                        LibrarySelectionBar(count: selectedBookIDs.count) {
                            isConfirmingDeleteSelection = true
                        }
                    }
                }
                .onChange(of: model.items) { pruneSelection() }
                .onChange(of: horizontalSizeClass) {
                    if horizontalSizeClass != .regular { endSelecting() }
                }
                .alert(
                    Text("Delete \(selectedBookIDs.count) Books?"),
                    isPresented: $isConfirmingDeleteSelection
                ) {
                    Button("Delete", role: .destructive, action: deleteSelection)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Their pages will be removed from Folio.")
                }
            #endif
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.folder, .zip],
                allowsMultipleSelection: false,
                onCompletion: importPicked
            )
            .alert(
                "Rename Book",
                isPresented: isPresenting($bookToRename),
                presenting: bookToRename
            ) { book in
                TextField("Title", text: $renameTitle)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    let title = renameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task { await model.rename(book.id, to: title) }
                }
                .disabled(renameTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .alert(
                Text("Delete “\(bookToDelete?.title ?? "")”?"),
                isPresented: isPresenting($bookToDelete),
                presenting: bookToDelete
            ) { book in
                Button("Delete", role: .destructive) {
                    Task { await model.removeBook(book.id) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Its pages will be removed from Folio.")
            }
            .alert(
                shownNotice?.title ?? "",
                isPresented: noticeIsPresented,
                presenting: shownNotice
            ) { notice in
                // The only place a Notice leaves the model. The cancel role makes
                // Escape go through this button too.
                Button("OK", role: .cancel) { model.dismissNotice(notice.id) }
            } message: { notice in
                Text(notice.message)
            }
            .onChange(of: model.presentedNotice?.id, initial: true) { showPresentedNotice() }
            .onChange(of: shownNotice) { showPresentedNotice() }
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
            LibraryEmptyView { isImporting = true }
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
            #endif
        }
    }

    #if os(macOS)
        /// Presents the delete confirmation for the selected Book; nil with no
        /// selection, which leaves the Delete key and Edit → Delete disabled.
        private var deleteSelectedBook: (() -> Void)? {
            guard let book = selectedBook else { return nil }
            return { bookToDelete = book }
        }

        private var selectedBook: Book? {
            guard let selection else { return nil }
            for case .book(let book) in model.items where book.id == selection {
                return book
            }
            return nil
        }
    #else
        private var hasBooks: Bool {
            model.items.contains { if case .book = $0 { true } else { false } }
        }

        /// Leaves Select mode; the selection does not outlive it.
        private func endSelecting() {
            isSelecting = false
            selectedBookIDs = []
        }

        /// Drops selected Books that have left the Library.
        private func pruneSelection() {
            var present = Set<BookID>()
            for case .book(let book) in model.items { present.insert(book.id) }
            selectedBookIDs.formIntersection(present)
            if !hasBooks { endSelecting() }
        }

        private func deleteSelection() {
            let ids = selectedBookIDs
            endSelecting()
            Task {
                for id in ids { await model.removeBook(id) }
            }
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
                        Button("Rename…", systemImage: "pencil") {
                            renameTitle = book.title
                            bookToRename = book
                        }
                        Button("Delete Book", systemImage: "trash", role: .destructive) {
                            bookToDelete = book
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
                Task { await model.open(book.id) }
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    selection = book.id
                    gridIsFocused = true
                }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                Task { await model.open(book.id) }
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
                    Task { await model.open(book.id) }
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

    private func importPicked(_ result: Result<[URL], any Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importSource(url)
        case .failure(let error):
            AppLog.library.error(
                "File picker failed: \(String(describing: error), privacy: .public)")
            model.filePickerFailed()
        }
    }

    /// Imports a Source picked in the file picker or dropped on the window.
    private func importSource(_ url: URL) {
        Task {
            let isAccessing = url.startAccessingSecurityScopedResource()
            await model.importSource(url)
            if isAccessing { url.stopAccessingSecurityScopedResource() }
        }
    }

    /// Shows the model's presented Notice once no alert is showing one.
    ///
    /// The alert is driven by `shownNotice`, not by the model, and the hand-over
    /// waits for the alert to close: `shownNotice` becomes nil only when SwiftUI
    /// writes `isPresented = false`, and the next Notice is set only after that,
    /// plus `noticeHandOverDelay` so the closing alert has finished animating out
    /// and `isPresented` is seen going false then true.
    ///
    /// This cannot lose a Notice: only the OK button removes one from the model,
    /// and only the Notice that button was shown with (`dismissNotice(_:)` checks
    /// the id). A late `isPresented = false` that clears the next Notice only
    /// hides it; it is still first in the model and is shown again from here.
    private func showPresentedNotice() {
        guard shownNotice == nil, let next = model.presentedNotice else { return }
        Task {
            try? await Task.sleep(for: Self.noticeHandOverDelay)
            guard shownNotice == nil, model.presentedNotice?.id == next.id else { return }
            shownNotice = next
        }
    }

    private static let noticeHandOverDelay = Duration.milliseconds(150)

    /// Setting false only hides the alert; the model keeps the Notice until OK.
    private var noticeIsPresented: Binding<Bool> {
        Binding(
            get: { shownNotice != nil },
            set: { if !$0 { shownNotice = nil } }
        )
    }

    private func isPresenting(_ book: Binding<Book?>) -> Binding<Bool> {
        Binding(
            get: { book.wrappedValue != nil },
            set: { if !$0 { book.wrappedValue = nil } }
        )
    }
}
