import FolioCore
import SwiftUI
import UniformTypeIdentifiers

/// The root of one window: the NavigationStack that holds the Library and the Book
/// being read, and every dialog and status line a Notice or a request can raise.
///
/// Dialogs live here, not on the Library screen, so that each screen the stack shows,
/// now and later, is beneath them: a Notice appears over whichever screen is on top.
/// For the same reason a Book opens as a push onto the stack and not as a full-screen
/// cover, which SwiftUI presents in a layer above this view (reading design,
/// "What the owner decided").
struct LibraryWindow: View {
    let model: LibraryModel

    /// The Books pushed on this window's stack; one per window on Mac.
    @State private var path: [Book] = []
    /// Every dialog this window shows: the one on screen and those waiting.
    @State private var queue = PresentationQueue()
    /// The Rename dialog's text field; seeded when the Rename is asked for.
    @State private var renameTitle = ""

    init(model: LibraryModel) {
        self.model = model
    }

    var body: some View {
        NavigationStack(path: $path) {
            LibraryView(model: model, request: request, open: open)
                .navigationDestination(for: Book.self) { book in
                    ReadingView(book: book, model: model) { _ = path.popLast() }
                }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if path.isEmpty, let notice = model.statusNotice {
                LibraryStatusLine(notice: notice) { model.dismissNotice(notice.id) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !path.isEmpty, let notice = model.statusNotice {
                LibraryStatusLine(notice: notice) { model.dismissNotice(notice.id) }
            }
        }
        #if os(macOS)
            .focusedSceneValue(\.libraryImporterIsPresented, importerIsPresented)
            .libraryDropTarget(onImport: importSource)
        #endif
        .background { dialogHost }
        .onChange(of: model.presentedNotice?.id, initial: true) { requestPresentedNotice() }
    }

    /// Records the open, then pushes the Book unless the Library no longer has it.
    private func open(_ book: Book) {
        Task {
            if await model.open(book.id) { path.append(book) }
        }
    }

    /// Carries every dialog modifier. Keyed by the current Presentation's id,
    /// so each Presentation gets a fresh view. That a changed `.id` makes a new
    /// view is documented SwiftUI behaviour. That the new view presents its
    /// dialog when it appears with `isPresented` already true is observed
    /// behaviour, not documented; the owner's manual check is the evidence.
    /// Without the key, a Notice promoted in the same update as the one before
    /// it would leave `isPresented` true with only the presented value
    /// changed, and SwiftUI might never show it.
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
                    Button("Delete", role: .destructive) {
                        Task { await model.removeBooks(ids) }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { _ in
                    Text("Their pages will be removed from Folio.")
                }
            #endif
            .id(queue.current?.id)
    }

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

    /// Asks for the model's presented Notice; the queue ignores it if it is
    /// already on screen or waiting.
    private func requestPresentedNotice() {
        guard let notice = model.presentedNotice else { return }
        request(.notice(notice))
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
