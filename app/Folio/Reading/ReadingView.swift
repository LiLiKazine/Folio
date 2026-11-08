import FolioCore
import SwiftUI

/// The open Book: its Pages one per screen, a tap to show or hide the chrome, and
/// the Reading Position moving with every Page turn.
struct ReadingView: View {
    let book: Book
    let model: LibraryModel
    let close: () -> Void

    /// The Page being read, 0-based. Every change is a Page turn the Library records.
    @State private var index: Int
    @State private var chromeIsVisible = false
    /// Decodes this Book's Pages at the window's size; nil until the size is known.
    @State private var cache: PageImageCache?
    /// The size `cache` decodes to; the cache is rebuilt only when this changes.
    @State private var cacheDecodeSize = 0
    @FocusState private var isFocused: Bool
    @Environment(\.displayScale) private var displayScale

    init(book: Book, model: LibraryModel, close: @escaping () -> Void) {
        self.book = book
        self.model = model
        self.close = close
        _index = State(initialValue: Self.startIndex(for: book))
    }

    /// The Page a Book opens on: its Reading Position, the first Page when it has none,
    /// and the last Page when an older edition left the position past the end.
    static func startIndex(for book: Book) -> Int {
        max(min(book.readingPosition ?? 0, book.pages.count - 1), 0)
    }

    /// The size Pages are decoded to for a window whose longer side is `windowPixels`
    /// pixels: rounded up to a multiple of 256, so resizing a Mac window rebuilds the
    /// cache in steps and not at every pixel.
    static func decodeSize(forWindowPixels windowPixels: Int) -> Int {
        let step = 256
        return max((windowPixels + step - 1) / step, 1) * step
    }

    var body: some View {
        pager
            .ignoresSafeArea()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if chromeIsVisible {
                    ReadingChrome(index: $index, pageCount: book.pages.count)
                }
            }
            .navigationTitle(book.title)
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button("Close", systemImage: "xmark", action: close)
                        .help("Close")
                }
            }
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarVisibility(chromeIsVisible ? .visible : .hidden, for: .navigationBar)
                .statusBarHidden(!chromeIsVisible)
            #else
                .focusable()
                .focusEffectDisabled()
                .focused($isFocused)
                .onKeyPress(.leftArrow) { turn(by: -1) }
                .onKeyPress(.rightArrow) { turn(by: 1) }
                .onExitCommand(perform: close)
            #endif
            .onGeometryChange(for: Int.self) { geometry in
                Int((max(geometry.size.width, geometry.size.height) * displayScale).rounded())
            } action: { pixels in
                let size = Self.decodeSize(forWindowPixels: pixels)
                if size != cacheDecodeSize { makeCache(maxPixelSize: size) }
            }
            .onAppear {
                #if os(macOS)
                    isFocused = true
                #endif
                // A Book never read starts at its first Page, so the position exists from
                // the first open.
                if book.readingPosition == nil {
                    Task { await model.turnPage(book.id, to: index) }
                }
            }
            .onChange(of: index) {
                Task { await model.turnPage(book.id, to: index) }
                Task { await cache?.prefetch(around: index) }
            }
    }

    /// The Pages side by side, one per screen width, paging as the reader swipes.
    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(book.pages.indices, id: \.self) { page in
                    PageView(
                        index: page, pageCount: book.pages.count, cache: cache,
                        onTap: { chromeIsVisible.toggle() }
                    )
                    .containerRelativeFrame(.horizontal)
                    .id(page)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: scrolledPage)
    }

    /// The scroll view's position as a Page index. The scroll view writes nil while it
    /// has no position; a turn is only a real Page.
    private var scrolledPage: Binding<Int?> {
        Binding(
            get: { index },
            set: { if let page = $0 { index = page } }
        )
    }

    /// Moves `delta` Pages, stopping at the first and last Page.
    private func turn(by delta: Int) -> KeyPress.Result {
        let target = index + delta
        guard book.pages.indices.contains(target) else { return .handled }
        withAnimation { index = target }
        return .handled
    }

    private func makeCache(maxPixelSize: Int) {
        let urls = book.pages.indices.map { model.pageURL(for: book, at: $0) }
        let cache = PageImageCache(urls: urls, maxPixelSize: maxPixelSize)
        self.cache = cache
        cacheDecodeSize = maxPixelSize
        Task { await cache.prefetch(around: index) }
    }
}
