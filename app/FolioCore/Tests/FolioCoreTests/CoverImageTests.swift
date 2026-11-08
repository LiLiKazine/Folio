import Foundation
import Testing

@testable import FolioCore

@Suite("Cover rendering")
struct CoverImageTests {
    @Test("downsamples to 600 on the long side, keeping aspect")
    func downsample() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let page = directory.url.appendingPathComponent("page.png")
        let cover = directory.url.appendingPathComponent(CoverImage.fileName)
        try ImageFixtures.png(width: 1200, height: 1800, at: page)

        try CoverImage.render(page: page, to: cover)

        let size = try ImageFixtures.pixelSize(of: cover)
        #expect(size.width == 400)
        #expect(size.height == 600)
    }

    @Test("leaves small Pages at their size")
    func small() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let page = directory.url.appendingPathComponent("page.png")
        let cover = directory.url.appendingPathComponent(CoverImage.fileName)
        try ImageFixtures.png(width: 300, height: 450, at: page)

        try CoverImage.render(page: page, to: cover)

        let size = try ImageFixtures.pixelSize(of: cover)
        #expect(size.width == 300)
        #expect(size.height == 450)
    }

    @Test("undecodable Page throws")
    func garbage() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let page = try directory.file("x.jpg", bytes: Data("nope".utf8))
        let cover = directory.url.appendingPathComponent(CoverImage.fileName)

        #expect(throws: CoverImageError.undecodable) {
            try CoverImage.render(page: page, to: cover)
        }
    }
}
