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
            urls: urls, screenWidthPixels: 8, perPageBudget: pageBytes, cacheBudget: 2 * pageBytes)
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

    @Test("with the top Page retained, prefetch keeps it and the next, and releases the third")
    func budgetReleasesTheOldestOthers() async throws {
        let directory = try PNGFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (urls, pageBytes) = try makePages(count: 4, in: directory)
        let cache = makeCache(urls: urls, pageBytes: pageBytes)

        await cache.retain(top: 0)
        await cache.prefetch(around: 0)  // decodes Pages 0, 1 and 2 (there is no Page -1)
        #expect(await cache.decodeCount == 3)

        // Pages 0 and 1 were kept: asking for them decodes nothing.
        #expect(await cache.slices(at: 0) != nil)
        #expect(await cache.slices(at: 1) != nil)
        #expect(await cache.decodeCount == 3)

        // Page 2 did not fit, so it was released and is decoded again.
        #expect(await cache.slices(at: 2) != nil)
        #expect(await cache.decodeCount == 4)
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

    @Test("a Page that cannot be decoded is remembered as such, not retried")
    func brokenPageNotRetried() async throws {
        let directory = try PNGFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let broken = directory.appending(path: "0001.png")
        try Data("not a Page".utf8).write(to: broken)
        let cache = SlicedPageCache(urls: [broken], screenWidthPixels: 8)

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
        let cache = SlicedPageCache(urls: [], screenWidthPixels: 8)

        #expect(await cache.slices(at: 0) == nil)
        await cache.prefetch(around: 0)
        await cache.retain(top: 0)
        #expect(await cache.decodeCount == 0)
    }
}
