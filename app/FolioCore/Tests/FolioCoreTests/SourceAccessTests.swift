import Foundation
import Testing

@testable import FolioCore

@Suite("Source access")
struct SourceAccessTests {
    @Test("in-memory bookmark roundtrips to the same URL")
    func roundtrip() async throws {
        let access = InMemorySourceAccess()
        let url = URL(fileURLWithPath: "/tmp/x/Chapter 01")
        let data = try access.bookmark(for: url)
        let seen = try await access.withAccess(to: data) { $0 }
        #expect(seen.path == url.path)
    }

    @Test("unavailable paths throw .unavailable")
    func unavailable() async throws {
        var access = InMemorySourceAccess()
        let url = URL(fileURLWithPath: "/tmp/x/Gone")
        access.unavailable.insert(url.path)
        let data = try access.bookmark(for: url)
        await #expect(throws: SourceAccessError.unavailable) {
            try await access.withAccess(to: data) { $0 }
        }
    }

    @Test("volume capacity reports a positive number for the temp directory")
    func capacity() throws {
        #expect(
            try VolumeStorageCapacity().availableBytes(at: FileManager.default.temporaryDirectory)
                > 0)
    }

    @Test("fixed capacity returns its configured bytes")
    func fixedCapacity() throws {
        #expect(
            try FixedStorageCapacity(bytes: 42).availableBytes(at: URL(fileURLWithPath: "/")) == 42)
    }
}
