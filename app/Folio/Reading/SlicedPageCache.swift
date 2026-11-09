import CoreGraphics
import Foundation

/// Holds the decoded slices of the Pages of one Vertical strip within a byte budget, for
/// the strip's whole life. Every decode runs on this one actor, one at a time, also across
/// a change of width, so two tall Pages are never fully decoded at once.
actor SlicedPageCache {
    /// What decoding one Page produced. A Page that cannot be decoded is held as `nil`
    /// slices, so it is not retried every time the reader scrolls past it.
    private struct Held {
        let slices: [CGImage]?
        let bytes: Int
        var lastUsed: Int
    }

    private let urls: [URL]
    /// The width in pixels Pages are decoded at now (see `changeWidth(to:)`).
    private var widthPixels: Int
    private let perPageBudget: Int
    private let cacheBudget: Int
    private var held: [Int: Held] = [:]
    /// The Pages the budget never releases: the one at the top of the screen and the next.
    private var retained: Set<Int> = []
    /// Counts uses, so "oldest used" is a number.
    private var clock = 0
    /// How many decodes have run; lets tests see what the cache kept and what it released.
    private(set) var decodeCount = 0
    /// The decodes running now.
    private var decodesRunning = 0
    /// The most decodes that have run at the same time; lets tests see that they never
    /// overlap.
    private(set) var mostDecodesAtOnce = 0

    /// The bytes of the slices held now.
    var heldBytes: Int { held.values.reduce(0) { $0 + $1.bytes } }

    /// `urls` locate the Book's Pages in reading order; `widthPixels` is the strip's width
    /// in pixels, until `changeWidth(to:)` changes it. `cacheBudget` defaults to three
    /// Pages' worth at `perPageBudget`.
    init(
        urls: [URL], widthPixels: Int,
        perPageBudget: Int = SlicedPage.perPageBudget(), cacheBudget: Int? = nil
    ) {
        self.urls = urls
        self.widthPixels = widthPixels
        self.perPageBudget = perPageBudget
        self.cacheBudget = cacheBudget ?? 3 * perPageBudget
    }

    /// The slices of the Page at `index`, decoded now if the cache does not hold them; nil
    /// when the index is outside the Book, the Page cannot be decoded, or the calling task
    /// was cancelled before the decode began. After each decode the cache releases Pages to
    /// fit the cache budget, keeping the Page returned and the pair `retain(top:)` named.
    func slices(at index: Int) async -> [CGImage]? {
        guard urls.indices.contains(index) else { return nil }
        if let existing = held[index] {
            held[index]?.lastUsed = tick()
            return existing.slices
        }
        // The Page that asked has scrolled away (its task was cancelled); decoding for it
        // would only delay the Page the reader landed on.
        guard !Task.isCancelled else { return nil }
        decodesRunning += 1
        mostDecodesAtOnce = max(mostDecodesAtOnce, decodesRunning)
        let slices = decode(index)
        decodesRunning -= 1
        held[index] = Held(
            slices: slices, bytes: slices.map(SlicedPage.bytes(of:)) ?? 0, lastUsed: tick())
        decodeCount += 1
        applyBudget(keeping: index)
        return slices
    }

    /// Marks `top` and the Page after it as the ones never to release, then releases the
    /// other Pages, oldest used first, until the slices held fit the cache budget.
    func retain(top: Int) {
        retained = [top, top + 1]
        applyBudget()
    }

    /// Decodes at `widthPixels` from now on. Every Page held was decoded at the old width,
    /// so all are let go and each is decoded again when it is next asked for; the Pages
    /// `retain(top:)` named stay the ones never to release. The width already in use
    /// changes nothing, and so does a call from a task that was cancelled: the strip
    /// cancels its width task when a newer width replaces it, and Swift does not promise
    /// to run calls waiting on an actor in the order they were made (SE-0306), so the
    /// newer width may already be in use.
    func changeWidth(to widthPixels: Int) {
        guard widthPixels != self.widthPixels, !Task.isCancelled else { return }
        self.widthPixels = widthPixels
        held = [:]
    }

    private func decode(_ index: Int) -> [CGImage]? {
        let url = urls[index]
        guard let pageSize = PageImage.pixelSize(url: url) else {
            AppLog.reading.info(
                "A Page could not be decoded: \(url.lastPathComponent, privacy: .private)")
            return nil
        }
        let width = SlicedPage.decodeWidth(
            pageSize: pageSize, screenWidthPixels: widthPixels, budget: perPageBudget)
        return SlicedPage.decode(url: url, width: width)
    }

    private func tick() -> Int {
        clock += 1
        return clock
    }

    /// Releases Pages, least recently used first, until the slices held fit the cache
    /// budget. Never releases the retained pair or `extra`, the Page being returned.
    private func applyBudget(keeping extra: Int? = nil) {
        var total = heldBytes
        let releasable = held.filter {
            !retained.contains($0.key) && $0.key != extra && $0.value.bytes > 0
        }
        .sorted { $0.value.lastUsed < $1.value.lastUsed }
        for (index, entry) in releasable {
            guard total > cacheBudget else { return }
            held[index] = nil
            total -= entry.bytes
        }
    }
}
