import CoreGraphics
import SwiftUI

/// Where the strip's scroll view is, measured from the top of its first Page: the two
/// numbers the top-of-screen rule needs, read from the scroll view's geometry.
struct StripScroll: Equatable {
    /// How far the strip is scrolled, in points from the top of the first Page.
    let offset: CGFloat
    /// The height of the visible area, in points.
    let viewportHeight: CGFloat

    init(offset: CGFloat, viewportHeight: CGFloat) {
        self.offset = offset
        self.viewportHeight = viewportHeight
    }

    /// Apple documents that the content offset "may extend before zero ... when the
    /// content insets of the scroll view are non-zero", so the top inset is added back to
    /// measure from the first Page.
    init(_ geometry: ScrollGeometry) {
        offset = geometry.contentOffset.y + geometry.contentInsets.top
        viewportHeight = geometry.visibleRect.height
    }
}

/// The open Book read Vertical: every Page at the strip's width and at the height its
/// pixel size gives, top to bottom with nothing between, in one scroll view. The Page at
/// the top of the screen is the Page being read.
struct VerticalStripView: View {
    /// The Book's Page files in reading order.
    let pageURLs: [URL]
    /// Each Page's pixel size, read before the strip is shown so no Page's height changes
    /// once it is; nil for a Page whose file is not an image, which takes a square.
    let pixelSizes: [CGSize?]
    /// The Page being read, 0-based: the Page at the top of the screen. The reader's own
    /// scrolling sets it; a change from outside (the slider, a key, a switch, opening the
    /// Book) scrolls that Page's top to the top of the screen.
    @Binding var index: Int
    /// A single tap on the strip, which shows or hides the chrome.
    let onTap: () -> Void

    /// Whether `phase` is the reader moving the strip rather than code. Apple describes
    /// `interacting` as "the user is interacting with the scroll view" and `decelerating` as
    /// the user having "stopped interacting" while the strip coasts on. `tracking` is a
    /// finger down where "the user hasn't started a scroll", so a tap is not a scroll; `idle`
    /// is no scrolling, and `animating` is "the result of a programmatic scroll".
    nonisolated static func isReaderScrolling(_ phase: ScrollPhase) -> Bool {
        switch phase {
        case .interacting, .decelerating: true
        case .idle, .tracking, .animating: false
        @unknown default: false
        }
    }

    /// Decodes the Pages at the strip's width in pixels; nil until the width is known.
    @State private var cache: SlicedPageCache?
    /// The width in pixels `cache` decodes to; the cache is rebuilt only when this changes.
    @State private var cacheWidthPixels = 0
    /// The Page at the top of the screen by the top-of-screen rule, at the last report of
    /// where the strip is; nil before the first report.
    @State private var topPage: Int?
    /// Whether the reader, not code, is moving the strip now (see `isReaderScrolling`).
    @State private var readerIsScrolling = false
    /// The Pages kept decoded for where the strip is (`StripGeometry.pagesToDecode`); none
    /// before the first report of where the strip is.
    @State private var pagesToDecode = 0..<0
    /// Where the strip was at the last report, with the geometry it was laid out in; read
    /// when the width or the zoom changes, to keep the reader's place.
    @State private var lastReport = LastReport()
    /// Moves the strip to an exact offset when the width or the zoom changes.
    @State private var position = ScrollPosition()
    /// The scale the strip rests at; 1 is fit to the screen's width.
    @State private var scale: CGFloat = 1
    /// The scale while a pinch is in progress, relative to `scale`.
    @GestureState private var pinch: CGFloat = 1
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { frame in
            strip(width: frame.size.width)
        }
    }

    private var liveScale: CGFloat {
        min(max(scale * pinch, 1), PageView.maximumScale)
    }

    /// The strip for a screen `width` points wide.
    private func strip(width: CGFloat) -> some View {
        let pageWidth = width * liveScale
        let stripGeometry = StripGeometry(
            pixelSizes: pixelSizes, width: pageWidth, displayScale: displayScale)
        return ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                // A plain stack, not a lazy one: Apple documents that a lazy stack "only
                // calculates the geometry for subviews as they become visible" ("Creating
                // performant scrollable stacks"), and the top-of-screen rule needs every Page
                // exactly where `stripGeometry` puts it.
                VStack(spacing: 0) {
                    ForEach(pageURLs.indices, id: \.self) { page in
                        Group {
                            if pagesToDecode.contains(page) {
                                StripPage(
                                    index: page, pageCount: pageURLs.count, width: pageWidth,
                                    cache: cache)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(
                            width: pageWidth, height: stripGeometry.heights[page], alignment: .top
                        )
                        .clipped()
                        .id(page)
                    }
                }
            }
            .scrollPosition($position)
            // At fit the strip is exactly as wide as the screen; it only moves sideways when
            // zoomed.
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .onScrollGeometryChange(for: StripScroll.self) {
                StripScroll($0)
            } action: { _, scroll in
                follow(scroll, in: stripGeometry, byReader: readerIsScrolling)
            }
            .onScrollPhaseChange { oldPhase, newPhase, context in
                readerIsScrolling = Self.isReaderScrolling(newPhase)
                // Where the strip is when the reader starts or stops moving it, so the Page
                // they stop on is never missed.
                follow(
                    StripScroll(context.geometry), in: stripGeometry,
                    byReader: Self.isReaderScrolling(oldPhase) || readerIsScrolling)
            }
            .onChange(of: index, initial: true) {
                // A Page already at the top needs no scroll. That is always so when the
                // reader's own scrolling set `index`, and scrolling to the Page's top then
                // would pull them back while they scroll.
                guard index != topPage else { return }
                proxy.scrollTo(index, anchor: .top)
            }
            // A new width (the window resized, the screen turned, a zoom) changes every
            // Page's height, so the strip is moved to the same place inside the Page under the
            // top of the screen, centred across.
            .onChange(of: stripGeometry) { _, newGeometry in
                guard let scroll = lastReport.scroll, let reported = lastReport.geometry else {
                    return
                }
                position.scrollTo(
                    x: (pageWidth - width) / 2,
                    y: newGeometry.offset(keepingPlaceOf: scroll.offset, in: reported))
            }
            .contentShape(.rect)
            .gesture(
                TapGesture(count: 2).onEnded { toggleZoom() }
                    .exclusively(before: TapGesture().onEnded { onTap() })
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in
                        scale = min(max(scale * value.magnification, 1), PageView.maximumScale)
                    }
            )
        }
        .onChange(of: Int((width * displayScale).rounded()), initial: true) { _, pixels in
            if pixels != cacheWidthPixels { makeCache(widthPixels: pixels) }
        }
        // The Pages on screen ask for their own slices (see `pagesToDecode`); the cache is
        // told only which Page is at the top, so its budget never releases it or the next.
        .task(id: RetainRequest(index: index, cache: cache.map(ObjectIdentifier.init))) {
            await cache?.retain(top: index)
        }
    }

    /// Notes the Page at the top and the Pages to keep decoded for `scroll` and, when the
    /// reader is the one moving the strip, makes the Page at the top the Page being read.
    /// Code moving the strip (opening, a jump, a new width) never changes the Page being
    /// read this way.
    private func follow(_ scroll: StripScroll, in stripGeometry: StripGeometry, byReader: Bool) {
        lastReport.scroll = scroll
        lastReport.geometry = stripGeometry
        let window = stripGeometry.pagesToDecode(
            offset: scroll.offset, viewportHeight: scroll.viewportHeight)
        if window != pagesToDecode { pagesToDecode = window }
        let page = stripGeometry.pageAtTop(
            offset: scroll.offset, viewportHeight: scroll.viewportHeight)
        if page != topPage { topPage = page }
        if byReader, page != index { index = page }
    }

    /// Zooms in or back to fit at once, not animated: the strip must already have its new
    /// size when it is moved to keep the reader's place, because the scroll view clamps a
    /// move "to only scroll to the size of its actual content" (`ScrollPosition`).
    private func toggleZoom() {
        scale = scale > 1 ? 1 : PageView.zoomedScale
    }

    private func makeCache(widthPixels: Int) {
        cache = SlicedPageCache(urls: pageURLs, screenWidthPixels: widthPixels)
        cacheWidthPixels = widthPixels
    }
}

/// Where the strip was at the last report of its scroll view, and the geometry it was laid
/// out in. A reference, so that noting it on every frame of scrolling does not redraw the
/// strip; nothing on screen shows it.
private final class LastReport {
    var scroll: StripScroll?
    var geometry: StripGeometry?
}

/// The Page at the top, for the cache in use.
private struct RetainRequest: Equatable {
    let index: Int
    let cache: ObjectIdentifier?
}

/// One Page in the strip that is kept decoded: its slices edge to edge, nothing while they
/// are decoded, or the placeholder when the Page cannot be shown. It exists only while the
/// Page is among `pagesToDecode`, so a Page that leaves them lets go of its slices.
private struct StripPage: View {
    /// The Page's place in the Book, 0-based.
    let index: Int
    let pageCount: Int
    /// The Page's width in points; every slice is drawn at it.
    let width: CGFloat
    /// Nil until the strip's width is known; the Page shows nothing until then.
    let cache: SlicedPageCache?

    /// What decoding the Page produced.
    private enum Loaded {
        case loading
        case slices([CGImage])
        case unavailable
    }

    @State private var loaded = Loaded.loading

    var body: some View {
        content
            .task(id: cache.map(ObjectIdentifier.init)) {
                guard let cache else { return }
                let slices = await cache.slices(at: index)
                // Cancelled means this Page left the screen: nil is no verdict on the file.
                guard !Task.isCancelled else { return }
                loaded = slices.map(Loaded.slices) ?? .unavailable
            }
    }

    @ViewBuilder private var content: some View {
        switch loaded {
        case .loading:
            Color.clear
        case .slices(let slices):
            VStack(spacing: 0) {
                ForEach(slices.indices, id: \.self) { slice in
                    Image(decorative: slices[slice], scale: 1)
                        .resizable()
                        .frame(
                            width: width,
                            height: width * CGFloat(slices[slice].height)
                                / CGFloat(slices[slice].width))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Page \(index + 1) of \(pageCount)"))
            .accessibilityAddTraits(.isImage)
        case .unavailable:
            PageUnavailable(index: index)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
