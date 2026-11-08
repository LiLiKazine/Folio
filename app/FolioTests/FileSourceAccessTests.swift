import FolioCore
import Foundation
import Testing

@testable import Folio

@Suite("File source access")
struct FileSourceAccessTests {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileSourceAccessTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("bookmark to a temp folder resolves to the same folder")
    func roundtrip() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let access = FileSourceAccess()
        let bookmark = try access.bookmark(for: directory)
        let resolvedPath = try await access.withAccess(to: bookmark) { url in
            url.standardizedFileURL.resolvingSymlinksInPath().path
        }

        #expect(resolvedPath == directory.standardizedFileURL.resolvingSymlinksInPath().path)
    }

    @Test("bookmark to a deleted folder is unavailable")
    func deleted() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let access = FileSourceAccess()
        let bookmark = try access.bookmark(for: directory)
        try FileManager.default.removeItem(at: directory)

        await #expect(throws: SourceAccessError.unavailable) {
            try await access.withAccess(to: bookmark) { _ in () }
        }
    }
}
