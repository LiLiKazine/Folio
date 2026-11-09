import CoreGraphics
import Foundation
import Testing

@testable import Folio

@Suite("SlicedPageCache")
struct SlicedPageCacheTests {
    /// Writes `count` 8 x 8 Pages and returns their URLs in order, with the byte size of
    /// one decoded Page; the budgets in these tests are multiples of that size, so
    /// "two Pages fit and a third does not" does not depend on how ImageIO pads rows.
    private func makePages(count: Int, in directory: URL) throws -> (urls: [URL], pageBytes: Int) {
        let urls = try (1...count).map { number in
            let url = directory.appending(path: String(format: "%04d.png", number))
            try PNGFixture.write(to: url, width: 8, height: 8)
            return url
        }
        let decoded = try #require(SlicedPage.decode(url: urls[0], width: 8))
        return (urls, SlicedPage.bytes(of: decoded))
    }

    private func makeCache(urls: [URL], pageBytes: Int) -> SlicedPageCache {
        SlicedPageCache(
            urls: urls, widthPixels: 8, perPageBudget: pageBytes, cacheBudget: 2 * pageBytes)
    }

    @Test("a Page is decoded once and reused")
    func decodesOnce() async throws {
        let directory = try PNGFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (urls, pageBytes) = try makePages(count: 3, in: directory)
        let cache = makeCache(urls: urls, pageBytes: pageBytes)

        let first = await cache.slices(at: 0)
        let second = await cache.slices(at: 0)

        #expect(first != nil)
        #expect(second != nil)
        #expect(await cache.decodeCount == 1)
    }

    @Test(
        "with the top Page retained, a Page over the budget is kept until the next decode, which releases it"
    )
    func nextDecodeReleasesTheOldestOther() async throws {
        let directory = try PNGFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (urls, pageBytes) = try makePages(count: 4, in: directory)
        let cache = makeCache(urls: urls, pageBytes: pageBytes)

        await cache.retain(top: 0)
        for index in 0...2 { #expect(await cache.slices(at: index) != nil) }
        #expect(await cache.decodeCount == 3)
        // Page 2 is one Page over the budget, but it is the Page just handed back.
        #expect(await cache.heldBytes == 3 * pageBytes)

        #expect(await cache.slices(at: 3) != nil)
        #expect(await cache.decodeCount == 4)

        // Pages 0 and 1 were kept: asking for them decodes nothing.
        #expect(await cache.slices(at: 0) != nil)
        #expect(await cache.slices(at: 1) != nil)
        #expect(await cache.decodeCount == 4)

        // Page 2 was released when Page 3 was decoded, so it is decoded again.
        #expect(await cache.slices(at: 2) != nil)
        #expect(await cache.decodeCount == 5)
    }

    @Test(
        "after every decode the cache holds the top Page, the next, and the Page just handed back, nothing more"
    )
    func budgetHoldsAfterEveryDecode() async throws {
        let directory = try PNGFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (urls, pageBytes) = try makePages(count: 9, in: directory)
        let cache = makeCache(urls: urls, pageBytes: pageBytes)

        await cache.retain(top: 0)
        _ = await cache.slices(at: 0)
        _ = await cache.slices(at: 1)
        #expect(await cache.heldBytes == 2 * pageBytes)

        // The reader jumps to Page 5, and the strip asks for the Pages around it.
        await cache.retain(top: 5)
        #expect(await cache.heldBytes == 2 * pageBytes)
        for (index, pagesHeld) in [(5, 2), (6, 2), (7, 3), (4, 3)] {
            #expect(await cache.slices(at: index) != nil)
            #expect(await cache.heldBytes == pagesHeld * pageBytes, "after Page \(index)")
        }

        // Held now: Pages 5 and 6, retained, and Page 4, just handed back; Page 7 went.
        let decodes = await cache.decodeCount
        for index in [5, 6, 4] { _ = await cache.slices(at: index) }
        #expect(await cache.decodeCount == decodes)
        #expect(await cache.slices(at: 7) != nil)
        #expect(await cache.decodeCount == decodes + 1)
    }

    @Test("retain releases the Pages the reader left behind, oldest used first")
    func retainReleasesOldest() async throws {
        let directory = try PNGFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (urls, pageBytes) = try makePages(count: 4, in: directory)
        let cache = makeCache(urls: urls, pageBytes: pageBytes)

        _ = await cache.slices(at: 0)
        _ = await cache.slices(at: 1)
        _ = await cache.slices(at: 0)  // Page 0 is now newer than Page 1
        _ = await cache.slices(at: 2)
        #expect(await cache.decodeCount == 3)

        await cache.retain(top: 2)  // keeps Page 2 (and 3, not held); over budget by one Page

        // Page 1 was the oldest used of the others, so it went; Page 0 stayed.
        #expect(await cache.slices(at: 0) != nil)
        #expect(await cache.decodeCount == 3)
        #expect(await cache.slices(at: 1) != nil)
        #expect(await cache.decodeCount == 4)
    }

    @Test("a width change lets go of every Page held, and the next read decodes at the new width")
    func widthChangeDropsHeldPages() async throws {
        let directory = try PNGFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (urls, pageBytes) = try makePages(count: 3, in: directory)
        let cache = makeCache(urls: urls, pageBytes: pageBytes)

        await cache.retain(top: 0)
        _ = await cache.slices(at: 0)
        _ = await cache.slices(at: 1)
        #expect(await cache.decodeCount == 2)

        await cache.changeWidth(to: 4)

        #expect(await cache.heldBytes == 0)
        let narrower = try #require(await cache.slices(at: 0))
        #expect(narrower.allSatisfy { $0.width == 4 })
        #expect(await cache.decodeCount == 3)

        // The width already in use is no change: the Page held stays.
        await cache.changeWidth(to: 4)
        _ = await cache.slices(at: 0)
        #expect(await cache.decodeCount == 3)
    }

    @Test("a width change asked for by a task that was cancelled changes nothing")
    func cancelledWidthChangeChangesNothing() async throws {
        let directory = try PNGFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (urls, pageBytes) = try makePages(count: 3, in: directory)
        let cache = makeCache(urls: urls, pageBytes: pageBytes)
        _ = await cache.slices(at: 0)

        let change = Task {
            while !Task.isCancelled { await Task.yield() }
            await cache.changeWidth(to: 4)
        }
        change.cancel()
        await change.value

        let slices = try #require(await cache.slices(at: 0))
        #expect(slices.allSatisfy { $0.width == 8 })
        #expect(await cache.decodeCount == 1)
    }

    @Test("reads on either side of width changes decode one at a time")
    func readsAcrossWidthChangesDoNotOverlap() async throws {
        let directory = try PNGFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // Tall enough that decodes running side by side would overlap in time.
        let urls = try (1...6).map { number in
            let url = directory.appending(path: String(format: "%04d.png", number))
            try PNGFixture.write(to: url, width: 64, height: 4000)
            return url
        }
        let cache = SlicedPageCache(urls: urls, widthPixels: 64)

        await withTaskGroup(of: Void.self) { group in
            for index in urls.indices {
                group.addTask { _ = await cache.slices(at: index) }
                group.addTask { await cache.changeWidth(to: index.isMultiple(of: 2) ? 32 : 64) }
            }
        }

        #expect(await cache.decodeCount == urls.count)
        #expect(await cache.mostDecodesAtOnce == 1)
    }

    @Test("a Page that cannot be decoded is remembered as such, not retried")
    func brokenPageNotRetried() async throws {
        let directory = try PNGFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let broken = directory.appending(path: "0001.png")
        try Data("not a Page".utf8).write(to: broken)
        let cache = SlicedPageCache(urls: [broken], widthPixels: 8)

        #expect(await cache.slices(at: 0) == nil)
        #expect(await cache.slices(at: 0) == nil)
        #expect(await cache.decodeCount == 1)
    }

    @Test("a decode asked for by a task that was cancelled does not run")
    func cancelledRequestDoesNotDecode() async throws {
        let directory = try PNGFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (urls, pageBytes) = try makePages(count: 3, in: directory)
        let cache = makeCache(urls: urls, pageBytes: pageBytes)

        let request = Task {
            while !Task.isCancelled { await Task.yield() }
            return await cache.slices(at: 1)
        }
        request.cancel()

        #expect(await request.value == nil)
        #expect(await cache.decodeCount == 0)
    }

    @Test("an index outside the Pages yields nil without decoding")
    func indexOutOfRange() async throws {
        let cache = SlicedPageCache(urls: [], widthPixels: 8)

        #expect(await cache.slices(at: 0) == nil)
        await cache.retain(top: 0)
        #expect(await cache.decodeCount == 0)
    }
}
