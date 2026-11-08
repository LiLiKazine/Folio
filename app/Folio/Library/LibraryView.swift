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
                    Button("Import", systemImage: "plus") { isImporting = true }
                }
            }
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
                    let title = renameTitle
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
                Text("Couldn't Import “\(model.failureAlert?.sourceName ?? "")”"),
                isPresented: failureAlertIsPresented,
                presenting: model.failureAlert
            ) { _ in
                Button("OK") {}
            } message: { alert in
                Text(alert.reason.localizedDescription)
            }
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
        }
    }

    @ViewBuilder private func card(for item: FolioCore.LibraryItem) -> some View {
        switch item {
        case .book(let book):
            Button {
                Task { await model.open(book.id) }
            } label: {
                BookCard(book: book, coverURL: model.coverURL(for: book))
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Rename…", systemImage: "pencil") {
                    renameTitle = book.title
                    bookToRename = book
                }
                Button("Delete Book", systemImage: "trash", role: .destructive) {
                    bookToDelete = book
                }
            }
        case .importRecord(let record):
            ImportCard(record: record, liveProgress: model.liveProgress[record.id]) {
                Task { await model.retryImport(record.id) }
            }
            .contextMenu {
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
        }
    }

    private func importPicked(_ result: Result<[URL], any Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                let isAccessing = url.startAccessingSecurityScopedResource()
                await model.importSource(url)
                if isAccessing { url.stopAccessingSecurityScopedResource() }
            }
        case .failure(let error):
            AppLog.library.error(
                "File picker failed: \(String(describing: error), privacy: .public)")
        }
    }

    private var failureAlertIsPresented: Binding<Bool> {
        Binding(
            get: { model.failureAlert != nil },
            set: { if !$0 { model.failureAlert = nil } }
        )
    }

    private func isPresenting(_ book: Binding<Book?>) -> Binding<Bool> {
        Binding(
            get: { book.wrappedValue != nil },
            set: { if !$0 { book.wrappedValue = nil } }
        )
    }
}
