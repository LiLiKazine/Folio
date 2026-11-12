import Foundation
import Synchronization
import Testing

@testable import FolioCore

@Suite("Import pipeline")
struct ImportPipelineTests {
    private static let plentyOfStorage = FixedStorageCapacity(bytes: .max)

    /// Records every staging root a pipeline obtains, so a test can check it is gone.
    private final class StagingRoots: Sendable {
        private let roots = Mutex<[URL]>([])

        var all: [URL] { roots.withLock { $0 } }

        /// The system item-replacement directory for `booksDirectory`, recorded.
        func provide(for booksDirectory: URL) throws -> URL {
            let root = try ImportPipeline.itemReplacementDirectory(for: booksDirectory)
            roots.withLock { $0.append(root) }
            return root
        }
    }

    private struct NoItemReplacementDirectory: Error {}

    private struct Fixture {
        let directory: TemporaryDirectory
        let booksDirectory: URL
        /// Stands in for the system temporary directory, which holds the fallback staging.
        let temporaryDirectory: URL
        let stagingRoots = StagingRoots()
        let pipeline: ImportPipeline

        init(
            storage: StorageCapacity = ImportPipelineTests.plentyOfStorage,
            itemReplacementAvailable: Bool = true
        ) throws {
            directory = try TemporaryDirectory()
            booksDirectory = directory.url.appending(path: "Books", directoryHint: .isDirectory)
            temporaryDirectory = directory.url.appending(path: "Temp", directoryHint: .isDirectory)
            pipeline = ImportPipeline(
                booksDirectory: booksDirectory, storage: storage,
                temporaryDirectory: temporaryDirectory,
                stagingRootProvider: { [stagingRoots] booksDirectory in
                    guard itemReplacementAvailable else { throw NoItemReplacementDirectory() }
                    return try stagingRoots.provide(for: booksDirectory)
                })
        }

        var fallbackStagingRoot: URL {
            temporaryDirectory.appending(path: ImportPipeline.fallbackStagingName)
        }

        /// Everything under the Books directory, plus every staging root a run used that
        /// still exists, plus everything inside the fallback staging folder.
        func leftovers() -> [String] {
            let manager = FileManager.default
            let books = (try? manager.contentsOfDirectory(atPath: booksDirectory.path)) ?? []
            let roots = stagingRoots.all.filter { manager.fileExists(atPath: $0.path) }
            let fallback =
                (try? manager.contentsOfDirectory(atPath: fallbackStagingRoot.path)) ?? []
            return books + roots.map { "staging root \($0.path)" }
                + fallback.map { "\(ImportPipeline.fallbackStagingName)/\($0)" }
        }

        /// A folder Source holding real PNG images at the given relative paths.
        func folderSource(_ names: [String]) throws -> URL {
            let source = directory.url.appending(path: "Source", directoryHint: .isDirectory)
            for name in names {
                let url = source.appending(path: name)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try ImageFixtures.png(width: 40, height: 60, at: url)
            }
            return source
        }

        /// A zip Source holding real PNG images under the given entry names.
        func zipSource(_ names: [String], fileName: String = "Source.zip") throws -> URL {
            let image = directory.url.appending(path: "fixture.png")
            try ImageFixtures.png(width: 40, height: 60, at: image)
            let data = try Data(contentsOf: image)
            var writer = ZipWriter()
            for name in names { writer.add(name, data: data, method: .deflate) }
            let url = directory.url.appending(path: fileName)
            try writer.write(to: url)
            return url
        }

        func run(_ source: URL, bookID: BookID = BookID()) async throws -> Book {
            try await pipeline.run(source: source, bookID: bookID, title: "Title") { _, _ in }
        }

        /// Asserts `book` is the two-Page Book a, b imports to, and that its folder is complete.
        func expectImported(_ book: Book, bookID: BookID) throws {
            let folder = booksDirectory.appending(path: bookID.rawValue.uuidString)
            #expect(book.id == bookID)
            #expect(book.folderName == bookID.rawValue.uuidString)
            #expect(book.pages.map(\.fileName) == ["0001.png", "0002.jpg"])
            #expect(book.coverFileName == CoverImage.fileName)
            for page in book.pages {
                #expect(
                    FileManager.default.fileExists(
                        atPath: folder.appending(path: "pages/\(page.fileName)").path))
            }
            #expect(
                FileManager.default.fileExists(
                    atPath: folder.appending(path: CoverImage.fileName).path))
            #expect(leftovers() == [bookID.rawValue.uuidString])
        }
    }

    @Test("folder Source becomes a Book with ordered renamed Pages and a Cover")
    func folder() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        let source = try fixture.folderSource(["b.jpg", "a.png"])
        let bookID = BookID()
        let importedAt = Date(timeIntervalSince1970: 1_000)

        let book = try await fixture.pipeline.run(
            source: source, bookID: bookID, title: "Vol.3", importedAt: importedAt
        ) { _, _ in }

        try fixture.expectImported(book, bookID: bookID)
        #expect(book.title == "Vol.3")
        #expect(book.importedAt == importedAt)
        #expect(book.lastOpenedAt == nil)
        #expect(book.readingPosition == nil)
    }

    @Test("a newly imported Book reads Vertical")
    func newBookReadsVertical() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        let source = try fixture.folderSource(["a.png"])

        let book = try await fixture.pipeline.run(
            source: source, bookID: BookID(), title: "Vol.3", importedAt: .now
        ) { _, _ in }

        #expect(book.readingMode == .vertical)
    }

    @Test("zip Source is expanded and imported like a folder")
    func zip() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        let source = try fixture.zipSource(["b.jpg", "a.png"])
        let bookID = BookID()

        let book = try await fixture.run(source, bookID: bookID)

        try fixture.expectImported(book, bookID: bookID)
    }

    @Test(".ZIP in capitals is treated as a zip")
    func upperZip() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        let source = try fixture.zipSource(["b.jpg", "a.png"], fileName: "Source.ZIP")
        let bookID = BookID()

        let book = try await fixture.run(source, bookID: bookID)

        try fixture.expectImported(book, bookID: bookID)
    }

    @Test(".cbz and .CBZ are zips under another name and are imported like a zip")
    func cbz() async throws {
        for fileName in ["Source.cbz", "Source.CBZ"] {
            let fixture = try Fixture()
            defer { fixture.directory.remove() }
            let source = try fixture.zipSource(["b.jpg", "a.png"], fileName: fileName)
            let bookID = BookID()

            let book = try await fixture.run(source, bookID: bookID)

            try fixture.expectImported(book, bookID: bookID)
        }
    }

    @Test("no images fails with noImagesFound and leaves nothing")
    func noImages() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        try fixture.directory.file("Source/notes.txt")
        let source = fixture.directory.url.appending(path: "Source")

        await #expect(throws: ImportFailure(reason: .noImagesFound)) {
            try await fixture.run(source)
        }
        #expect(fixture.leftovers().isEmpty)
    }

    @Test("garbage zip fails with unreadableZip")
    func unreadable() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        let source = try fixture.directory.file("Source.zip", bytes: Data("not a zip".utf8))

        await #expect(throws: ImportFailure(reason: .unreadableZip)) {
            try await fixture.run(source)
        }
        #expect(fixture.leftovers().isEmpty)
    }

    @Test("zip64 fails with unsupportedZip")
    func unsupported() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        var writer = ZipWriter()
        writer.zip64 = true
        writer.add("a.png", data: Data([0x89, 0x50]), method: .stored)
        let source = fixture.directory.url.appending(path: "Source.zip")
        try writer.write(to: source)

        await #expect(throws: ImportFailure(reason: .unsupportedZip)) {
            try await fixture.run(source)
        }
        #expect(fixture.leftovers().isEmpty)
    }

    @Test("insufficient storage fails before copying")
    func storage() async throws {
        let fixture = try Fixture(storage: FixedStorageCapacity(bytes: 1))
        defer { fixture.directory.remove() }
        let folder = try fixture.folderSource(["a.png", "b.png"])
        let zip = try fixture.zipSource(["a.png", "b.png"])

        for source in [folder, zip] {
            await #expect(throws: ImportFailure(reason: .notEnoughStorage)) {
                try await fixture.run(source)
            }
        }
        #expect(fixture.stagingRoots.all.count == 2)
        #expect(fixture.leftovers().isEmpty)
    }

    /// Holds the importing Task so its own `progress` closure can cancel it.
    private actor Canceller {
        private var task: Task<Book, any Error>?
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func hold(_ task: Task<Book, any Error>) {
            self.task = task
            for continuation in waiting { continuation.resume() }
            waiting.removeAll()
        }

        func cancel() async {
            if task == nil {
                await withCheckedContinuation { waiting.append($0) }
            }
            task?.cancel()
        }
    }

    @Test("cancellation leaves nothing behind")
    func cancel() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        let source = try fixture.folderSource((1...50).map { "\($0).png" })
        let canceller = Canceller()
        let pipeline = fixture.pipeline

        let task = Task {
            try await pipeline.run(source: source, bookID: BookID(), title: "Title") {
                pagesDone, _ in
                if pagesDone == 5 { await canceller.cancel() }
            }
        }
        await canceller.hold(task)

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(fixture.leftovers().isEmpty)
    }

    private actor ProgressLog {
        private(set) var calls: [[Int]] = []
        func record(_ done: Int, _ total: Int) { calls.append([done, total]) }
    }

    @Test("progress starts at zero and ends at total")
    func progress() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        let source = try fixture.folderSource(["1.png", "2.png", "3.png"])
        let log = ProgressLog()

        _ = try await fixture.pipeline.run(source: source, bookID: BookID(), title: "Title") {
            await log.record($0, $1)
        }

        #expect(await log.calls == [[0, 3], [1, 3], [2, 3], [3, 3]])
    }

    @Test("a Page deleted from the Source before it is copied fails with sourceUnavailable")
    func pageDeletedBeforeCopy() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        let source = try fixture.folderSource(["1.png", "2.png"])
        let doomed = source.appending(path: "2.png")

        await #expect(throws: ImportFailure(reason: .sourceUnavailable)) {
            try await fixture.pipeline.run(source: source, bookID: BookID(), title: "Title") {
                done, _ in
                if done == 0 { try? FileManager.default.removeItem(at: doomed) }
            }
        }
        #expect(fixture.leftovers().isEmpty)
    }

    @Test("read-side errors are told apart from write-side ones")
    func readFailureClassification() {
        #expect(ImportPipeline.isReadFailure(CocoaError(.fileReadNoSuchFile)))
        #expect(ImportPipeline.isReadFailure(CocoaError(.fileReadNoPermission)))
        #expect(ImportPipeline.isReadFailure(CocoaError(.fileNoSuchFile)))
        #expect(ImportPipeline.isReadFailure(POSIXError(.ENOENT)))
        #expect(ImportPipeline.isReadFailure(POSIXError(.EACCES)))
        #expect(!ImportPipeline.isReadFailure(CocoaError(.fileWriteNoPermission)))
        #expect(!ImportPipeline.isReadFailure(CocoaError(.fileWriteOutOfSpace)))
    }

    @Test("staging is on the same volume as the Books directory")
    func stagingVolume() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        let source = try fixture.folderSource(["a.png"])
        let volumes = Mutex<[String]>([])
        let books = fixture.booksDirectory

        _ = try await fixture.pipeline.run(source: source, bookID: BookID(), title: "Title") {
            done, _ in
            guard done == 1, let root = fixture.stagingRoots.all.first else { return }
            for url in [root, books] {
                let volume = try? url.resourceValues(forKeys: [.volumeIdentifierKey])
                    .volumeIdentifier
                volumes.withLock { $0.append(volume.map { "\($0)" } ?? "unknown") }
            }
        }

        let identifiers = volumes.withLock { $0 }
        #expect(identifiers.count == 2)
        #expect(!identifiers.contains("unknown"))
        #expect(Set(identifiers).count == 1)
        #expect(fixture.stagingRoots.all.count == 1)
        #expect(!fixture.stagingRoots.all[0].path.hasPrefix(fixture.booksDirectory.path))
    }

    @Test("without an item-replacement directory, staging falls back to FolioImport")
    func fallbackStaging() async throws {
        let fixture = try Fixture(itemReplacementAvailable: false)
        defer { fixture.directory.remove() }
        let source = try fixture.folderSource(["b.jpg", "a.png"])
        let bookID = BookID()
        let sawStaging = Mutex(false)
        let staging = fixture.fallbackStagingRoot.appending(path: bookID.rawValue.uuidString)

        let book = try await fixture.pipeline.run(source: source, bookID: bookID, title: "Title") {
            _, _ in
            if FileManager.default.fileExists(atPath: staging.path) {
                sawStaging.withLock { $0 = true }
            }
        }

        #expect(sawStaging.withLock { $0 })
        try fixture.expectImported(book, bookID: bookID)
    }

    @Test("a failed run under the fallback leaves nothing in FolioImport")
    func fallbackFailure() async throws {
        let fixture = try Fixture(itemReplacementAvailable: false)
        defer { fixture.directory.remove() }
        let source = try fixture.directory.file("Source.zip", bytes: Data("not a zip".utf8))

        await #expect(throws: ImportFailure(reason: .unreadableZip)) {
            try await fixture.run(source)
        }
        #expect(fixture.leftovers().isEmpty)
    }

    @Test("removeLeftoverStaging clears the fallback staging folder")
    func staging() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        let source = try fixture.folderSource(["a.png"])
        let bookID = BookID()
        _ = try await fixture.run(source, bookID: bookID)
        let name = ImportPipeline.fallbackStagingName
        try fixture.directory.file("Temp/\(name)/\(UUID().uuidString)/pages/0001.png")
        try fixture.directory.file("Temp/\(name)/\(UUID().uuidString)/expanded/a.png")

        try fixture.pipeline.removeLeftoverStaging()

        #expect(!FileManager.default.fileExists(atPath: fixture.fallbackStagingRoot.path))
        #expect(fixture.leftovers() == [bookID.rawValue.uuidString])
    }
}
