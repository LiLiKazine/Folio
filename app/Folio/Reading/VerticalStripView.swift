import CoreGraphics
import SwiftUI

/// Where the strip's scroll view is, measured from the top of its first Page: the two
/// numbers the top-of-screen rule needs, read from the scroll view's geometry.
struct StripScroll: Equatable {
    /// How far the strip is scrolled, in points from the top of the first Page.
    let offset: CGFloat
    /// The height of the visible area, in points.
    let viewportHeight: CGFloat
    /// How far the strip is scrolled sideways, in points from its left edge; 0 at fit,
    /// where the strip is no wider than the screen.
    let offsetX: CGFloat

    init(offset: CGFloat, viewportHeight: CGFloat, offsetX: CGFloat = 0) {
        self.offset = offset
        self.viewportHeight = viewportHeight
        self.offsetX = offsetX
    }

    /// Apple documents that the content offset "may extend before zero ... when the
    /// content insets of the scroll view are non-zero", so the top and leading insets are
    /// added back to measure from the first Page.
    init(_ geometry: ScrollGeometry) {
        offset = geometry.contentOffset.y + geometry.contentInsets.top
        viewportHeight = geometry.visibleRect.height
        offsetX = geometry.contentOffset.x + geometry.contentInsets.leading
    }
}

/// The open Book read Vertical: every Page at the strip's width and at the height its
/// pixel size gives, top to bottom with nothing between, in one scroll view. The Page at
/// the top of the screen is the Page being read.
struct VerticalStripView: View {
    /// Where each of the Book's Pages is stored, in reading order.
    let pageURLs: [URL]
    /// Each Page's pixel size, read before the strip is shown so no Page's height changes
    /// once it is; nil for a Page whose stored data is not a picture, which takes a square.
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

    /// Decodes the Pages one at a time for the strip's whole life; nil until the strip's
    /// width is known, then told every new width (`useWidth(pixels:)`).
    @State private var cache: SlicedPageCache?
    /// The width in pixels `cache` decodes at, once it has taken it; 0 before. The Pages
    /// kept decoded ask for their slices again when it changes.
    @State private var decodeWidthPixels = 0
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
    /// The scale the strip is laid out at; 1 is fit to the screen's width. A pinch
    /// changes it once, when the fingers lift (see `liveScale`).
    @State private var scale: CGFloat = 1
    /// The scale while a pinch is in progress, relative to `scale`; 1 between pinches.
    @GestureState private var pinch: CGFloat = 1
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { frame in
            strip(width: frame.size.width)
        }
    }

    /// The scale on screen: `scale` while the fingers pinch, between fit and the maximum.
    /// While a pinch is in progress the strip is only drawn at this scale, not laid out at
    /// it: `scaleEffect` "scales this view's rendered output", so every Page keeps its
    /// place and height, and the scroll view has nothing to move. The strip is laid out at
    /// the new scale once, when the fingers lift. Laying it out on every frame of the pinch
    /// was seen to make the scroll view report, for a moment, the new size together with
    /// the position from the old one; deep in a Book that position lies past the end of the
    /// shorter strip, so the Pages on screen were dropped and decoded again, a black flash
    /// on an iPhone, and the Reading Position moved to a later Page and back
    /// (reading-mode-implementation log, fix round 4).
    private var liveScale: CGFloat {
        min(max(scale * pinch, 1), PageView.maximumScale)
    }

    /// The point of the strip the pinch grows it about: the middle of the screen across,
    /// and the top of the screen down, as a fraction of the strip at `contentWidth` by
    /// `contentHeight`. That is the place the strip keeps when it is laid out at the new
    /// scale (`StripGeometry.offset(keepingPlaceOf:in:)`, centred across), so letting go
    /// does not move what is on screen. A strip with no size has no such point; the top
    /// centre stands in.
    nonisolated static func pinchAnchor(
        scroll: StripScroll, viewportWidth: CGFloat, contentWidth: CGFloat, contentHeight: CGFloat
    ) -> UnitPoint {
        guard contentWidth > 0, contentHeight > 0 else { return .top }
        return UnitPoint(
            x: (scroll.offsetX + viewportWidth / 2) / contentWidth, y: scroll.offset / contentHeight
        )
    }

    /// The strip for a screen `width` points wide.
    private func strip(width: CGFloat) -> some View {
        let widthPixels = Int((width * displayScale).rounded())
        let pageWidth = width * scale
        let stripGeometry = StripGeometry(
            pixelSizes: pixelSizes, width: pageWidth, displayScale: displayScale)
        let pinchAnchor = Self.pinchAnchor(
            scroll: lastReport.scroll ?? StripScroll(offset: 0, viewportHeight: 0),
            viewportWidth: width, contentWidth: pageWidth,
            contentHeight: stripGeometry.contentHeight)
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
                                    cache: cache, decodeWidthPixels: decodeWidthPixels)
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
                .scaleEffect(liveScale / scale, anchor: pinchAnchor)
            }
            .scrollPosition($position)
            // At fit the strip is exactly as wide as the screen, so it moves sideways only
            // when zoomed. A strip no taller than the screen does not bounce either, so it is
            // never pulled to an offset that the end-of-strip rule would read as its last Page.
            .scrollBounceBehavior(.basedOnSize, axes: [.horizontal, .vertical])
            .onScrollGeometryChange(for: StripScroll.self) {
                StripScroll($0)
            } action: { _, scroll in
                follow(scroll, in: stripGeometry, byReader: readerIsScrolling)
            }
            .onScrollPhaseChange { oldPhase, newPhase, context in
                readerIsScrolling = Self.isReaderScrolling(newPhase)
                // Where the strip is when the reader starts or stops moving it. The change that
                // ends their scrolling counts as theirs, so the Page they stop on is recorded
                // even when no report came after the last move; and when code jumps while the
                // strip is still coasting, the Page at the top when the coasting ends is
                // recorded the same way.
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
            // A new width (the window resized, the screen turned, a zoom once the fingers
            // lift) changes every Page's height, so the strip is moved to the same place inside
            // the Page under the top of the screen, centred across. When that place is the offset the strip
            // already had (at the very top of the strip, for one), the scroll view reports
            // nothing, as it reports only changes, so the Pages to decode are worked out here
            // for the new geometry. This is code moving the strip: it never changes the Page
            // being read.
            .onChange(of: stripGeometry) { _, newGeometry in
                guard let scroll = lastReport.scroll, let reported = lastReport.geometry else {
                    return
                }
                let offset = newGeometry.offset(keepingPlaceOf: scroll.offset, in: reported)
                position.scrollTo(x: (pageWidth - width) / 2, y: offset)
                follow(
                    StripScroll(offset: offset, viewportHeight: scroll.viewportHeight),
                    in: newGeometry, byReader: false)
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
        .task(id: widthPixels) { await useWidth(pixels: widthPixels) }
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

    /// Makes the cache at the strip's first width and tells it every later one, so every
    /// decode runs through the one cache, also while a Mac window is resized. The Pages
    /// kept decoded ask again only once the cache has taken the new width, so what they get
    /// is decoded at it. When a newer width cancels this task while the cache is busy, the
    /// newer one is used instead.
    private func useWidth(pixels: Int) async {
        if let cache {
            await cache.changeWidth(to: pixels)
            guard !Task.isCancelled else { return }
        } else {
            cache = SlicedPageCache(urls: pageURLs, widthPixels: pixels)
        }
        decodeWidthPixels = pixels
    }
}

/// Where the strip was at the last report of its scroll view, and the geometry it was laid
/// out in. A reference, so that noting it on every frame of scrolling does not redraw the
/// strip; nothing on screen shows it.
private final class LastReport {
    var scroll: StripScroll?
    var geometry: StripGeometry?
}

/// The Page at the top, and the cache to tell (none until the strip's width is known).
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
    /// The width in pixels `cache` decodes at; a new one asks for the slices again.
    let decodeWidthPixels: Int

    /// What decoding the Page produced.
    private enum Loaded {
        case loading
        case slices([CGImage])
        case unavailable
    }

    @State private var loaded = Loaded.loading

    var body: some View {
        content
            .task(id: decodeWidthPixels) {
                guard let cache else { return }
                let slices = await cache.slices(at: index)
                // Cancelled means this Page left the screen or the width changed: nil is no
                // verdict on the Page.
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
