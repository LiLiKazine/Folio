import FolioCore
import SwiftUI
import UniformTypeIdentifiers

/// The Library screen: every Book and every Import that has not produced one,
/// in an adaptive grid, with Import, rename, and delete.
struct LibraryView: View {
    let model: LibraryModel

    @Environment(\.scenePhase) private var scenePhase
    /// Every dialog this screen shows: the one on screen and those waiting.
    @State private var queue = PresentationQueue()
    /// The Rename dialog's text field; seeded when the Rename is asked for.
    @State private var renameTitle = ""
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

    init(model: LibraryModel) {
        self.model = model
    }

    var body: some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if let notice = model.statusNotice {
                    LibraryStatusLine(notice: notice) { model.dismissNotice(notice.id) }
                }
            }
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
                            request(.deleteSelection(selectedBookIDs))
                        }
                    }
                }
                .onChange(of: model.items) { pruneSelection() }
                .onChange(of: horizontalSizeClass) {
                    if horizontalSizeClass != .regular { endSelecting() }
                }
            #endif
            .background { dialogHost }
            .onChange(of: model.presentedNotice?.id, initial: true) { requestPresentedNotice() }
            .onAppear {
                Task { await model.reload() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await model.reload() }
                }
            }
    }

    /// Carries every dialog modifier. Keyed by the current Presentation's id,
    /// so each Presentation gets a fresh view: SwiftUI documents that a view
    /// whose `.id` changes is a new view, so it sees a new presentation
    /// request rather than a changed one. Without it, a Notice promoted in the
    /// same update as the one before it would leave `isPresented` true with
    /// only the presented value changed, and SwiftUI might never show it.
    private var dialogHost: some View {
        Color.clear
            .fileImporter(
                isPresented: isPresenting { $0 == .importPicker },
                allowedContentTypes: [.folder, .zip],
                allowsMultipleSelection: false,
                onCompletion: importPicked
            )
            .alert(
                "Rename Book",
                isPresented: isPresenting { if case .rename = $0 { true } else { false } },
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
                isPresented: isPresenting { if case .deleteBook = $0 { true } else { false } },
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
                noticeOnScreen?.title ?? "",
                isPresented: noticeIsPresented,
                presenting: noticeOnScreen
            ) { notice in
                // The cancel role makes Escape go through this button too.
                Button("OK", role: .cancel) { model.dismissNotice(notice.id) }
            } message: { notice in
                Text(notice.message)
            }
            #if os(iOS)
                .alert(
                    Text("Delete \(selectionToDelete?.count ?? 0) Books?"),
                    isPresented: isPresenting {
                        if case .deleteSelection = $0 { true } else { false }
                    },
                    presenting: selectionToDelete
                ) { ids in
                    Button("Delete", role: .destructive) { deleteSelection(ids) }
                    Button("Cancel", role: .cancel) {}
                } message: { _ in
                    Text("Their pages will be removed from Folio.")
                }
            #endif
            .id(queue.current?.id)
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
            #endif
        }
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

        /// Deletes the Books captured when the user tapped Delete, which may
        /// differ from the selection now.
        private func deleteSelection(_ ids: Set<BookID>) {
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

    /// The one way to ask for a dialog: it shows now if none is on screen,
    /// otherwise after every dialog asked for before it.
    private func request(_ presentation: Presentation) {
        if case .rename(let book) = presentation { renameTitle = book.title }
        queue.enqueue(presentation)
    }

    /// Asks for the model's presented Notice unless it is already on screen or waiting.
    private func requestPresentedNotice() {
        guard let notice = model.presentedNotice else { return }
        let presentation = Presentation.notice(notice)
        let isQueued =
            queue.current?.id == presentation.id
            || queue.pending.contains { $0.id == presentation.id }
        if !isQueued { request(presentation) }
    }

    /// True while the current dialog is of the kind `match` accepts. SwiftUI
    /// writes false when that dialog goes away, which promotes the next one.
    /// The setter acts only on the Presentation that was current when the
    /// binding was made, so a second false written through an old binding,
    /// after the next dialog has been promoted, cannot take that one away.
    private func isPresenting(_ match: @escaping (Presentation) -> Bool) -> Binding<Bool> {
        let shown = queue.current
        return Binding(
            get: { queue.current.map(match) ?? false },
            set: { isPresented in
                guard !isPresented, let shown, match(shown) else { return }
                queue.dismissed(shown.id)
            }
        )
    }

    /// Like `isPresenting(_:)` for the Notice dialog; however it goes away, the
    /// Notice leaves the model too, so it is never shown again. Acts only on the
    /// Notice that was on screen when the binding was made.
    private var noticeIsPresented: Binding<Bool> {
        let shown = noticeOnScreen
        return Binding(
            get: { noticeOnScreen != nil },
            set: { isPresented in
                guard !isPresented, let shown else { return }
                model.dismissNotice(shown.id)
                queue.dismissed(Presentation.notice(shown).id)
            }
        )
    }

    private var noticeOnScreen: Notice? {
        if case .notice(let notice) = queue.current { notice } else { nil }
    }

    private var bookToRename: Book? {
        if case .rename(let book) = queue.current { book } else { nil }
    }

    private var bookToDelete: Book? {
        if case .deleteBook(let book) = queue.current { book } else { nil }
    }

    #if os(iOS)
        private var selectionToDelete: Set<BookID>? {
            if case .deleteSelection(let ids) = queue.current { ids } else { nil }
        }
    #endif

    #if os(macOS)
        /// Reads whether the file picker is on screen; setting true asks for it
        /// through `request(_:)`. Published to File → Import… (⌘I).
        private var importerIsPresented: Binding<Bool> {
            Binding(
                get: { queue.current == .importPicker },
                set: { if $0 { request(.importPicker) } }
            )
        }
    #endif
}
