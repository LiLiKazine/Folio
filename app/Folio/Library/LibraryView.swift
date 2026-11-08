import FolioCore
import SwiftUI
import UniformTypeIdentifiers

/// The Library screen: every Book and every Import that has not produced one,
/// in an adaptive grid, with Import, rename, and delete.
struct LibraryView: View {
    let model: LibraryModel

    @Environment(\.scenePhase) private var scenePhase
    @State private var isImporting = false
    /// An Import asked for while another dialog was on screen; see `requestImport()`.
    @State private var importRequest = ImportRequestGate()
    /// True for `noticeHandOverDelay` after the last dialog started closing; a
    /// request then waits, because SwiftUI may still refuse the picker.
    @State private var isSettling = false
    /// The running settle; a dialog that opens and closes again restarts it.
    @State private var settleTask: Task<Void, Never>?
    @State private var bookToRename: Book?
    @State private var renameTitle = ""
    @State private var bookToDelete: Book?
    /// The Notice on screen; see `showPresentedNotice()`.
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
                        Button("Import…", systemImage: "plus") { requestImport() }
                            .help("Import a folder or zip")
                    #else
                        Button("Import", systemImage: "plus") { requestImport() }
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
                .focusedSceneValue(\.libraryImporterIsPresented, importerIsPresented)
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
            .onChange(of: isPresentingOtherDialog) { showPresentedNotice() }
            .onChange(of: canPresentImport) { settleAfterDialogs() }
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
            LibraryEmptyView { requestImport() }
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

    /// Shows the model's presented Notice once no dialog on this view is open.
    ///
    /// The Notice dialog is driven by `shownNotice`, not by the model, and the
    /// hand-over waits for every other dialog to close: `shownNotice` becomes nil
    /// only when SwiftUI writes `isPresented = false`, and the next Notice is set
    /// only after that, plus `noticeHandOverDelay` so the closing dialog has
    /// finished animating out and `isPresented` is seen going false then true.
    ///
    /// It also waits while this view shows the file picker, a Rename or Delete
    /// confirmation: SwiftUI refuses a second presentation from the same view
    /// without ever writing `isPresented = false`, so handing over then would
    /// leave `shownNotice` set and block every later Notice. Closing that dialog
    /// changes `isPresentingOtherDialog`, which calls this again.
    ///
    /// Only the OK button removes a Notice from the model, and only the Notice
    /// that button was shown with (`dismissNotice(_:)` checks the id). A late
    /// `isPresented = false` that clears the next Notice only hides it; it is
    /// still first in the model and is set again from here.
    private func showPresentedNotice() {
        guard shownNotice == nil, !isPresentingOtherDialog, let next = model.presentedNotice
        else { return }
        Task {
            // Ignored: this Task is never cancelled, and the guard below re-checks
            // everything before a Notice is shown.
            try? await Task.sleep(for: Self.noticeHandOverDelay)
            guard shownNotice == nil, !isPresentingOtherDialog,
                model.presentedNotice?.id == next.id
            else { return }
            shownNotice = next
        }
    }

    /// True while this view shows the file picker or a confirmation; a Notice waits.
    private var isPresentingOtherDialog: Bool {
        isImporting || isConfirming
    }

    /// True while this view shows a Rename or Delete confirmation.
    private var isConfirming: Bool {
        #if os(iOS)
            let isConfirmingSelection = isConfirmingDeleteSelection
        #else
            let isConfirmingSelection = false
        #endif
        return bookToRename != nil || bookToDelete != nil || isConfirmingSelection
    }

    /// True when no Notice or confirmation is on screen, so the file picker can open.
    private var canPresentImport: Bool {
        shownNotice == nil && !isConfirming
    }

    /// The one way to ask for the file picker: the toolbar button, the empty
    /// Library's button, and File → Import… (⌘I) on the Mac.
    ///
    /// SwiftUI refuses to open the picker while another dialog on this view is
    /// on screen, yet leaves `isImporting` true; the picker could then never open
    /// again and every later Notice would wait for it. So a request made then
    /// waits in `importRequest`, and `settleAfterDialogs()` opens the picker
    /// once that dialog has closed.
    private func requestImport() {
        if importRequest.request(canPresent: canPresentImport && !isSettling) {
            isImporting = true
        }
    }

    /// Starts the settle once the last dialog has started closing: for
    /// `noticeHandOverDelay` `isSettling` holds new requests, since SwiftUI may
    /// still be dismissing the dialog and would refuse the picker. When the
    /// settle ends, a waiting request opens the picker. If a Notice took the
    /// screen in the meantime, the request keeps waiting for it.
    private func settleAfterDialogs() {
        guard canPresentImport else { return }
        settleTask?.cancel()
        isSettling = true
        settleTask = Task {
            do {
                try await Task.sleep(for: Self.noticeHandOverDelay)
            } catch {
                // Cancelled: a newer settle has started and owns `isSettling`.
                return
            }
            isSettling = false
            guard canPresentImport, importRequest.dialogsCleared() else { return }
            isImporting = true
        }
    }

    /// Reads whether the picker is open; setting true asks for it through
    /// `requestImport()`. Published to File → Import… (⌘I) on the Mac.
    private var importerIsPresented: Binding<Bool> {
        Binding(
            get: { isImporting },
            set: { if $0 { requestImport() } else { isImporting = false } }
        )
    }

    private static let noticeHandOverDelay = Duration.milliseconds(150)

    /// Setting false only hides the dialog; the model keeps the Notice until OK.
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
