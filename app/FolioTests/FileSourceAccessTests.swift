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

    @Test("a local folder with ordinary files passes at once")
    func localFolderFiles() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let nested = directory.appending(path: "Chapter 1", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data([0xFF]).write(to: directory.appending(path: "1.png"))
        try Data([0xFF]).write(to: nested.appending(path: "2.png"))
        try Data([0xFF]).write(to: directory.appending(path: ".DS_Store"))

        let access = FileSourceAccess(downloadTimeout: .zero)
        let bookmark = try access.bookmark(for: directory)
        let start = ContinuousClock.now
        let ran = try await access.withAccess(to: bookmark) { _ in true }

        #expect(ran)
        #expect(ContinuousClock.now - start < .seconds(1))
    }

    @Test("a folder holding an iCloud placeholder that cannot download is not downloaded")
    func placeholderNotDownloaded() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data([0xFF]).write(to: directory.appending(path: "1.png"))
        try Data([0xFF]).write(to: directory.appending(path: ".2.png.icloud"))

        let access = FileSourceAccess(downloadTimeout: .zero)
        let bookmark = try access.bookmark(for: directory)

        await #expect(throws: SourceAccessError.notDownloaded) {
            try await access.withAccess(to: bookmark) { _ in () }
        }
    }
}
