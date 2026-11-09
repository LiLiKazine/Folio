import CoreGraphics
import FolioCore
import SwiftUI

/// The open Book in its Reading Mode: Page by Page, one Page per screen, or Vertical, one
/// strip of Pages. A tap shows or hides the chrome, and the Reading Position moves with
/// every Page turn.
struct ReadingView: View {
    let book: Book
    let model: LibraryModel
    let close: () -> Void

    /// The Page being read, 0-based. Every change is a Page turn the Library records.
    @State private var index: Int
    /// The Reading Mode on screen: the Book's own when it opens, then the reader's choice.
    @State private var mode: ReadingMode
    @State private var chromeIsVisible = false
    /// Decodes this Book's Pages at the window's size for Page by Page; nil until the size
    /// is known.
    @State private var cache: PageImageCache?
    /// The size `cache` decodes to; the cache is rebuilt only when this changes.
    @State private var cacheDecodeSize = 0
    /// Every Page's pixel size, for Vertical; read once, the first time the Book is shown
    /// Vertical, and nil until then. The strip is shown only once they are read, so no
    /// Page's height changes under the reader.
    @State private var pixelSizes: [CGSize?]?
    /// Where each of the Book's Pages is stored, worked out the first time it is needed
    /// (see `pageURLs`) and then kept for as long as this screen shows the Book.
    @State private var pageLocations = PageLocations()
    @FocusState private var isFocused: Bool
    @Environment(\.displayScale) private var displayScale

    init(book: Book, model: LibraryModel, close: @escaping () -> Void) {
        self.book = book
        self.model = model
        self.close = close
        _index = State(initialValue: Self.startIndex(for: book))
        _mode = State(initialValue: Self.startMode(for: book))
    }

    /// The Page a Book opens on: its Reading Position, the first Page when it has none,
    /// and the last Page when an older edition left the position past the end.
    static func startIndex(for book: Book) -> Int {
        max(min(book.readingPosition ?? 0, book.pages.count - 1), 0)
    }

    /// Where each of the Book's Pages is stored, in reading order. Not worked out in `init`:
    /// SwiftUI can make this view again every time the window updates, and a Book can have
    /// thousands of Pages.
    private var pageURLs: [URL] {
        pageLocations.urls { book.pages.indices.map { model.pageURL(for: book, at: $0) } }
    }

    /// The Reading Mode a Book opens in: its own.
    nonisolated static func startMode(for book: Book) -> ReadingMode {
        book.readingMode
    }

    /// The size Pages are decoded to for a window whose longer side is `windowPixels`
    /// pixels: rounded up to a multiple of 256, so resizing a Mac window rebuilds the
    /// cache in steps and not at every pixel.
    static func decodeSize(forWindowPixels windowPixels: Int) -> Int {
        let step = 256
        return max((windowPixels + step - 1) / step, 1) * step
    }

    var body: some View {
        content
            // A new identity for each Reading Mode: switching starts the other one afresh,
            // at fit, on the Page being read.
            .id(mode)
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
                if chromeIsVisible {
                    ToolbarItem(placement: .primaryAction) { readingModeControl }
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
                // Vertical keeps its own decoded Pages (see VerticalStripView).
                if mode == .pageByPage {
                    Task { await cache?.prefetch(around: index) }
                }
            }
            // The Page by Page cache starts empty after each switch, so the Pages it held for
            // one mode are let go while the other is on screen.
            .onChange(of: mode) { makeCache(maxPixelSize: cacheDecodeSize) }
            .task(id: mode) {
                guard mode == .vertical, pixelSizes == nil else { return }
                pixelSizes = await Self.pixelSizes(of: pageURLs)
            }
    }

    @ViewBuilder private var content: some View {
        switch mode {
        case .pageByPage:
            pager
        case .vertical:
            if let pixelSizes {
                VerticalStripView(
                    pageURLs: pageURLs, pixelSizes: pixelSizes, index: $index,
                    onTap: { chromeIsVisible.toggle() })
            } else {
                // The plain background the strip itself shows through, while the sizes are
                // read.
                Color.clear
            }
        }
    }

    /// Chooses the Reading Mode. The screen switches at once; the Library saves the choice
    /// behind it, and a failed save is only logged (see `LibraryModel.chooseReadingMode`).
    private func choose(_ chosen: ReadingMode) {
        mode = chosen
        Task { await model.chooseReadingMode(book.id, chosen) }
    }

    /// Page by Page or Vertical: a segmented control in the Mac toolbar, and a menu in the
    /// iPhone and iPad navigation bar, where two labelled segments beside the Title and
    /// Close would crowd it.
    @ViewBuilder private var readingModeControl: some View {
        let selection = Binding(get: { mode }, set: { choose($0) })
        #if os(macOS)
            Picker("Reading Mode", selection: selection) { readingModeOptions }
                .pickerStyle(.segmented)
        #else
            Menu {
                Picker("Reading Mode", selection: selection) { readingModeOptions }
                    .pickerStyle(.inline)
            } label: {
                Label("Reading Mode", systemImage: "book.pages")
            }
        #endif
    }

    @ViewBuilder private var readingModeOptions: some View {
        Text("Page by Page").tag(ReadingMode.pageByPage)
        Text("Vertical").tag(ReadingMode.vertical)
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

    /// Moves `delta` Pages, stopping at the first and last Page. Page by Page animates the
    /// turn. In Vertical a turn is a jump, code moving the strip, which must never count as
    /// the reader's scrolling (`VerticalStripView.isReaderScrolling`), so, like every jump
    /// in the strip, it is made without animation.
    private func turn(by delta: Int) -> KeyPress.Result {
        let target = index + delta
        guard book.pages.indices.contains(target) else { return .handled }
        switch mode {
        case .pageByPage: withAnimation { index = target }
        case .vertical: index = target
        }
        return .handled
    }

    private func makeCache(maxPixelSize: Int) {
        let cache = PageImageCache(urls: pageURLs, maxPixelSize: maxPixelSize)
        self.cache = cache
        cacheDecodeSize = maxPixelSize
        guard mode == .pageByPage else { return }
        Task { await cache.prefetch(around: index) }
    }

    /// Reads every Page's pixel size without decoding, away from the main actor.
    @concurrent private static func pixelSizes(of urls: [URL]) async -> [CGSize?] {
        urls.map(PageImage.pixelSize(url:))
    }
}

/// Keeps the Book's Page locations once they are worked out. A reference kept in `State`,
/// so it lasts as long as the screen, and keeping the locations does not redraw it.
@MainActor private final class PageLocations {
    private var urls: [URL]?

    /// The locations, worked out by `make` the first time they are asked for.
    func urls(_ make: () -> [URL]) -> [URL] {
        if let urls { return urls }
        let made = make()
        urls = made
        return made
    }
}
