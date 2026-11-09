import CoreGraphics
import Foundation

/// Holds the decoded slices of the Pages of one Vertical strip within a byte budget.
/// Decodes run one at a time (the actor), so two tall Pages are never fully decoded at
/// once.
actor SlicedPageCache {
    /// What decoding one Page produced. A Page that cannot be decoded is held as `nil`
    /// slices, so it is not retried every time the reader scrolls past it.
    private struct Held {
        let slices: [CGImage]?
        let bytes: Int
        var lastUsed: Int
    }

    private let urls: [URL]
    private let screenWidthPixels: Int
    private let perPageBudget: Int
    private let cacheBudget: Int
    private var held: [Int: Held] = [:]
    /// The Pages the budget never releases: the one at the top of the screen and the next.
    private var retained: Set<Int> = []
    /// Counts uses, so "oldest used" is a number.
    private var clock = 0
    /// How many decodes have run; lets tests see what the cache kept and what it released.
    private(set) var decodeCount = 0

    /// The bytes of the slices held now.
    var heldBytes: Int { held.values.reduce(0) { $0 + $1.bytes } }

    /// `urls` are the Book's Page files in reading order; `screenWidthPixels` is the
    /// strip's width in pixels. `cacheBudget` defaults to three Pages' worth at
    /// `perPageBudget`.
    init(
        urls: [URL], screenWidthPixels: Int,
        perPageBudget: Int = SlicedPage.perPageBudget(), cacheBudget: Int? = nil
    ) {
        self.urls = urls
        self.screenWidthPixels = screenWidthPixels
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
        let slices = decode(index)
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

    /// Decodes the Pages from one before `index` to two after it that exist, the Page at
    /// `index` first so the Page the reader is on is ready soonest. Each decode applies the
    /// cache budget (see `slices(at:)`), and the last step releases down to the budget with
    /// only the retained pair kept.
    func prefetch(around index: Int) async {
        for neighbour in [index, index + 1, index + 2, index - 1]
        where urls.indices.contains(neighbour) {
            _ = await slices(at: neighbour)
        }
        applyBudget()
    }

    private func decode(_ index: Int) -> [CGImage]? {
        let url = urls[index]
        guard let pageSize = PageImage.pixelSize(url: url) else {
            AppLog.reading.info(
                "A Page could not be decoded: \(url.lastPathComponent, privacy: .private)")
            return nil
        }
        let width = SlicedPage.decodeWidth(
            pageSize: pageSize, screenWidthPixels: screenWidthPixels, budget: perPageBudget)
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
