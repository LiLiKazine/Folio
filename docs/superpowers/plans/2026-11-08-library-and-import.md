# Library and Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Library screen that shows Books and in-flight Imports, and an Import pipeline that turns a picked folder or zip into a Book through a persisted, serially scheduled Import record.

**Architecture:** The domain lives in the `FolioCore` package: `Book`/`Page`/`Import` values, `BookRepository`/`ImportRepository` protocols with in-memory implementations, Source scanning, a zip reader on the Compression framework, the `ImportPipeline`, and the `Library` actor that schedules Imports and emits `LibraryEvent`s. The app target supplies the adapters: SwiftData repositories, a `FileSourceAccess` for security-scoped bookmarks, and SwiftUI views that read a `LibraryModel` built from repository queries and refreshed by events.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, SwiftData, Swift Testing, OSLog, Foundation, Compression, ImageIO, UniformTypeIdentifiers. No third-party packages.

**Spec:** `docs/superpowers/specs/2026-11-08-library-and-import-design.md` (glossary: `CONTEXT.md`)

## Global Constraints

- Use `CONTEXT.md` terms exactly in type names, identifiers, tests, commits, and UI copy; never the `_Avoid_` words (no "comic", "thumbnail", "dismiss", "task", "job", "progress" for Reading Position).
- Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY = complete`, warnings are errors (xcconfig for the app; `scripts/test.sh` passes `-Xswiftc -warnings-as-errors` for the package).
- Swift Testing only. OSLog only, no `print`. All user-facing strings via `String(localized:)` so they land in `Localizable.xcstrings`.
- Deployment targets iOS 26.0 and macOS 26.0. Sandbox stays on.
- No third-party dependencies. If zip reading on Compression proves unworkable, stop and raise it.
- Page extensions: `jpg, jpeg, png, heic, webp, gif` (case-insensitive). Skip hidden files and anything under `__MACOSX`.
- Order: natural sort of relative path (`localizedStandardCompare`), so `page2` precedes `page10`.
- Title: picked item's last path component without extension.
- Cover: first Page in order.
- Zip: stored (method 0) and deflate (method 8), data descriptors, UTF-8 names. Zip64 and encrypted entries fail as `unsupportedZip`.
- Invariants: Book written only after all Pages are in final place; at most one Import In Progress; Completed Import always has a Book id.
- Library order: `lastOpenedAt ?? importedAt`, newest first.
- Commands: `./scripts/test.sh` for the whole suite, `swift test --package-path app/FolioCore -Xswiftc -warnings-as-errors` for the package alone, `./scripts/verify.sh` as the gate. Commit after every task with the `structured-commit` format (`type(scope): subject`, Why / What changed / What was discovered, the attribution lines from the session).

## Review Focus

1. A zip entry whose name contains `../` or starts with `/` must be ignored, never written outside the staging folder (zip slip). Test in Task 3.
2. A file with `.ZIP` or `.Jpg` in capitals must be treated like lowercase. Tests in Tasks 2 and 6.
3. A Source with zero images (text files only, or an empty folder) fails with `noImagesFound` and leaves no staging folder. Test in Task 6.
4. A file with a `.zip` extension that is not a zip fails with `unreadableZip`, not a crash. Test in Task 3.
5. Not enough free space for the Source's total size fails with `notEnoughStorage` before any Page is copied. Test in Task 6 via an injected capacity provider.

---

## File Structure

FolioCore (`app/FolioCore/Sources/FolioCore/`):
- `Domain/Book.swift`: `Book`, `Page`, `BookID`.
- `Domain/Import.swift`: `Import`, `ImportID`, `ImportStatus`, `ImportFailureReason`.
- `Domain/LibraryEvent.swift`: `LibraryEvent`.
- `Domain/Repositories.swift`: `BookRepository`, `ImportRepository` protocols.
- `Domain/InMemoryRepositories.swift`: `InMemoryBookRepository`, `InMemoryImportRepository` actors.
- `Source/SourceScanner.swift`: finds and orders Page files, derives Title.
- `Source/ZipArchive.swift`: central-directory reader and entry extraction.
- `Source/Inflate.swift`: raw-deflate decoding on Compression.
- `Source/SourceAccess.swift`: `SourceAccess` protocol, `InMemorySourceAccess`.
- `Import/CoverImage.swift`: Cover rendering with ImageIO.
- `Import/ImportPipeline.swift`: one Import, start to finish, atomic.
- `Import/StorageCapacity.swift`: `StorageCapacity` protocol and `VolumeStorageCapacity`.
- `Library/Library.swift`: the actor: operations, scheduler, events, launch recovery.
- `Library/LibraryItem.swift`: `LibraryItem` (a Book or a non-Completed Import) and ordering.
- Delete `FolioCore.swift` once something else proves the link (Task 1).

FolioCore tests (`app/FolioCore/Tests/FolioCoreTests/`): one file per source file above, plus `Support/TemporaryDirectory.swift`, `Support/ZipWriter.swift`, `Support/ImageFixtures.swift`.

App (`app/Folio/`):
- `Persistence/BookModel.swift`, `Persistence/ImportModel.swift`: SwiftData `@Model`s.
- `Persistence/SwiftDataBookRepository.swift`, `Persistence/SwiftDataImportRepository.swift`.
- `Persistence/LibraryStorage.swift`: Books directory, backup exclusion, `ModelContainer`.
- `Persistence/FileSourceAccess.swift`: bookmarks and security scope.
- `Library/LibraryModel.swift`: `@Observable @MainActor` view model.
- `Library/LibraryView.swift`, `Library/BookCard.swift`, `Library/ImportCard.swift`, `Library/LibraryEmptyView.swift`, `Library/CoverView.swift`.
- `Library/LibraryCommands.swift` (macOS menu), `Library/LibraryDropTarget.swift` (macOS drop).
- `FolioApp.swift` modified; `ContentView.swift` deleted.

App tests (`app/FolioTests/`): `SwiftDataRepositoriesTests.swift`, `FileSourceAccessTests.swift`, `LibraryModelTests.swift`.

---

### Task 1: Domain values, events, and repository protocols

**Files:**
- Create: `app/FolioCore/Sources/FolioCore/Domain/Book.swift`
- Create: `app/FolioCore/Sources/FolioCore/Domain/Import.swift`
- Create: `app/FolioCore/Sources/FolioCore/Domain/LibraryEvent.swift`
- Create: `app/FolioCore/Sources/FolioCore/Domain/Repositories.swift`
- Create: `app/FolioCore/Sources/FolioCore/Domain/InMemoryRepositories.swift`
- Delete: `app/FolioCore/Sources/FolioCore/FolioCore.swift`, `app/FolioCore/Tests/FolioCoreTests/FolioCoreTests.swift`
- Modify: `app/Folio/FolioApp.swift` (replace the `FolioCore.version` log with `BookID` usage so the link stays proven)
- Test: `app/FolioCore/Tests/FolioCoreTests/InMemoryRepositoriesTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct BookID: Hashable, Codable, Sendable { public let rawValue: UUID; public init(_ rawValue: UUID = UUID()) }
  public struct ImportID: Hashable, Codable, Sendable { public let rawValue: UUID; public init(_ rawValue: UUID = UUID()) }
  public struct Page: Hashable, Codable, Sendable { public let fileName: String }
  public struct Book: Hashable, Codable, Sendable, Identifiable {
      public let id: BookID
      public var title: String
      public let folderName: String          // directory under the Books directory
      public let pages: [Page]               // reading order, explicit
      public let coverFileName: String       // rendered Cover image inside folderName
      public let importedAt: Date
      public var lastOpenedAt: Date?
      public var readingPosition: Int?       // index into pages
      public init(id:title:folderName:pages:coverFileName:importedAt:lastOpenedAt:readingPosition:)
  }
  public enum ImportStatus: String, Codable, Sendable { case queued, inProgress, failed, completed }
  public enum ImportFailureReason: String, Codable, Sendable, Equatable {
      case noImagesFound, unreadableZip, unsupportedZip, sourceNotDownloaded,
           notEnoughStorage, sourceUnavailable, cancelled
  }
  public struct Import: Hashable, Codable, Sendable, Identifiable {
      public let id: ImportID
      public var status: ImportStatus
      public let sourceBookmark: Data
      public let sourceName: String          // display name of the picked item
      public let title: String               // Title the Book will get
      public var pagesDone: Int
      public var pagesTotal: Int?
      public var failureReason: ImportFailureReason?
      public var bookID: BookID?
      public let createdAt: Date
      public var finishedAt: Date?
      public init(id:status:sourceBookmark:sourceName:title:pagesDone:pagesTotal:failureReason:bookID:createdAt:finishedAt:)
  }
  public enum LibraryEvent: Sendable, Equatable {
      case importQueued(ImportID, title: String)
      case importStarted(ImportID, pagesTotal: Int)
      case importProgressed(ImportID, pagesDone: Int, pagesTotal: Int)
      case importCompleted(ImportID, Book)
      case importFailed(ImportID, sourceName: String, reason: ImportFailureReason)
      case importRemoved(ImportID)
      case bookRenamed(BookID, title: String)
      case bookOpened(BookID, at: Date)
      case bookRemoved(BookID)
  }
  public protocol BookRepository: Sendable {
      func allBooks() async throws -> [Book]            // Library order
      func book(id: BookID) async throws -> Book?
      func add(_ book: Book) async throws
      func update(_ book: Book) async throws
      func remove(id: BookID) async throws
  }
  public protocol ImportRepository: Sendable {
      func imports(status: ImportStatus) async throws -> [Import]   // createdAt ascending
      func importRecord(id: ImportID) async throws -> Import?
      func add(_ record: Import) async throws
      func update(_ record: Import) async throws
      func remove(id: ImportID) async throws
  }
  public actor InMemoryBookRepository: BookRepository { public init() }
  public actor InMemoryImportRepository: ImportRepository { public init() }
  ```
  Library order helper, used by both in-memory and SwiftData repositories: `extension Array where Element == Book { public func inLibraryOrder() -> [Book] }` sorting by `lastOpenedAt ?? importedAt` descending.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite("In-memory repositories")
struct InMemoryRepositoriesTests {
    @Test("allBooks returns Library order: last opened or imported, newest first")
    func libraryOrder() async throws {
        let repo = InMemoryBookRepository()
        let old = makeBook(importedAt: .init(timeIntervalSince1970: 100))
        let opened = makeBook(importedAt: .init(timeIntervalSince1970: 50), lastOpenedAt: .init(timeIntervalSince1970: 500))
        let fresh = makeBook(importedAt: .init(timeIntervalSince1970: 300))
        for b in [old, opened, fresh] { try await repo.add(b) }
        #expect(try await repo.allBooks().map(\.id) == [opened.id, fresh.id, old.id])
    }
    @Test("update replaces a Book by id") func update() async throws { /* rename, fetch, expect new title */ }
    @Test("remove deletes by id") func remove() async throws { /* add, remove, expect nil */ }
    @Test("imports(status:) filters and orders by createdAt ascending") func importsByStatus() async throws { /* two queued, one failed; expect the two queued oldest first */ }
}
```
`makeBook(importedAt:lastOpenedAt:)` is a file-private helper building a one-Page Book.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path app/FolioCore -Xswiftc -warnings-as-errors`
Expected: compile failure, `InMemoryBookRepository` not found.

- [ ] **Step 3: Implement the five Domain files with the signatures above**

The in-memory repositories store dictionaries keyed by id. `allBooks()` returns `inLibraryOrder()`. `imports(status:)` filters then sorts by `createdAt`.

- [ ] **Step 4: Replace the smoke test and keep the app link proven**

Delete `FolioCore.swift` and `FolioCoreTests.swift`. In `FolioApp.swift`, replace the version log with `AppLog.general.info("Folio launched \(BookID().rawValue.uuidString, privacy: .public)")` so the app still fails to compile if the package is unlinked.

- [ ] **Step 5: Run the package tests and the app test suite**

Run: `./scripts/test.sh macos`
Expected: package tests PASS, `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

`feat(domain): add Book, Import, LibraryEvent, and repository protocols`

---

### Task 2: Source scanning and Title derivation

**Files:**
- Create: `app/FolioCore/Sources/FolioCore/Source/SourceScanner.swift`
- Create: `app/FolioCore/Tests/FolioCoreTests/Support/TemporaryDirectory.swift`
- Test: `app/FolioCore/Tests/FolioCoreTests/SourceScannerTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum SourceScanner {
      public static let pageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "webp", "gif"]
      /// Page files under `folder`, recursive, flattened, in reading order.
      /// Skips hidden files, anything under a `__MACOSX` directory, and non-Page extensions.
      public static func pageFiles(in folder: URL) throws -> [URL]
      /// Title for a picked item: last path component without extension.
      public static func title(forSource url: URL) -> String
  }
  ```
  Test support: `struct TemporaryDirectory { let url: URL; init() throws; func file(_ relativePath: String, bytes: Data = Data([0xFF])) throws -> URL; func remove() }`.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite("Source scanning")
struct SourceScannerTests {
    @Test("orders naturally so page2 precedes page10")
    func naturalOrder() throws {
        let dir = try TemporaryDirectory()
        for name in ["page10.jpg", "page2.jpg", "page1.jpg"] { try dir.file(name) }
        #expect(try SourceScanner.pageFiles(in: dir.url).map(\.lastPathComponent) == ["page1.jpg", "page2.jpg", "page10.jpg"])
    }
    @Test("flattens subfolders in relative-path order")
    func flattens() throws { /* "b/01.png", "a/02.png", "a/01.png" → a/01, a/02, b/01 */ }
    @Test("keeps only Page extensions, case-insensitively")
    func extensions() throws { /* "x.JPG","y.Png","z.txt","w.heic","v.webp","u.gif","t.jpeg","s.bmp" → 6 files, no txt/bmp */ }
    @Test("skips hidden files and __MACOSX")
    func skipsJunk() throws { /* ".DS_Store", "._01.jpg", "__MACOSX/01.jpg", "01.jpg" → ["01.jpg"] */ }
    @Test("empty folder yields no Pages") func empty() throws { /* [] */ }
    @Test("title is the item's own name without extension")
    func title() {
        #expect(SourceScanner.title(forSource: URL(fileURLWithPath: "/x/One Piece/Chapter 01")) == "Chapter 01")
        #expect(SourceScanner.title(forSource: URL(fileURLWithPath: "/x/op-vol3.zip")) == "op-vol3")
        #expect(SourceScanner.title(forSource: URL(fileURLWithPath: "/x/Vol.3.zip")) == "Vol.3")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path app/FolioCore -Xswiftc -warnings-as-errors --filter SourceScannerTests`
Expected: compile failure.

- [ ] **Step 3: Implement `SourceScanner` and `TemporaryDirectory`**

Use `FileManager.enumerator(at:includingPropertiesForKeys:options: [.skipsHiddenFiles])`, drop any URL whose path components contain `__MACOSX`, filter by lowercased extension, then sort by the path relative to `folder` with `localizedStandardCompare`. Title: strip only the final extension when it is `zip`; for folders return the last component as is (so `Vol.3` folder stays `Vol.3`), and for zips strip `.zip` only.

- [ ] **Step 4: Run tests to verify they pass**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

`feat(source): scan Source folders into ordered Pages and derive Title`

---

### Task 3: Zip reading on Compression

**Files:**
- Create: `app/FolioCore/Sources/FolioCore/Source/Inflate.swift`
- Create: `app/FolioCore/Sources/FolioCore/Source/ZipArchive.swift`
- Create: `app/FolioCore/Tests/FolioCoreTests/Support/ZipWriter.swift`
- Test: `app/FolioCore/Tests/FolioCoreTests/ZipArchiveTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum ZipError: Error, Equatable { case unreadable, unsupported }
  public struct ZipArchive: Sendable {
      public struct Entry: Sendable, Equatable { public let name: String; public let isDirectory: Bool; public let uncompressedSize: Int }
      public init(url: URL) throws(ZipError)           // reads the central directory only
      public var entries: [Entry]
      /// Extracts every file entry under `directory`, preserving relative paths.
      /// Ignores entries whose normalised path escapes `directory`. Calls `onEntry` after each file.
      public func extract(to directory: URL, onEntry: (Entry) -> Void = { _ in }) throws(ZipError)
  }
  enum Inflate { static func decode(_ data: Data, expectedSize: Int) throws(ZipError) -> Data }   // raw deflate via Compression COMPRESSION_ZLIB
  ```
  Test support: `struct ZipWriter { enum Method { case stored, deflate }; var useDataDescriptor: Bool = false; var zip64: Bool = false; var encryptedFlag: Bool = false; mutating func add(_ name: String, data: Data, method: Method); func write(to url: URL) throws }`. Deflate in the writer uses `compression_encode_buffer` with `COMPRESSION_ZLIB`.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite("Zip archive")
struct ZipArchiveTests {
    @Test("extracts stored entries") func stored() throws { /* add "a/1.jpg","2.png" stored; extract; files exist with same bytes */ }
    @Test("extracts deflate entries") func deflate() throws { /* 64 KiB of patterned data, deflate; extract; bytes equal */ }
    @Test("handles data descriptors (bit 3)") func dataDescriptor() throws { /* useDataDescriptor = true; extract ok */ }
    @Test("decodes UTF-8 names (bit 11)") func utf8Names() throws { /* "第01話/ページ1.jpg" roundtrips */ }
    @Test("rejects zip64 as unsupported") func zip64() throws { /* zip64 = true; #expect(throws: ZipError.unsupported) */ }
    @Test("rejects encrypted entries as unsupported") func encrypted() throws { /* encryptedFlag; extract throws .unsupported */ }
    @Test("not a zip is unreadable") func garbage() throws { /* write "hello" to x.zip; init throws .unreadable */ }
    @Test("ignores entries that escape the destination") func zipSlip() throws {
        /* names "../evil.jpg" and "/abs.jpg" and "ok.jpg"; after extract only ok.jpg exists under dir and nothing exists at dir.parent/evil.jpg */
    }
    @Test("ignores directory entries and __MACOSX") func dirs() throws { /* "a/", "__MACOSX/._x.jpg", "a/x.jpg" → only a/x.jpg written */ }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path app/FolioCore -Xswiftc -warnings-as-errors --filter ZipArchiveTests`
Expected: compile failure.

- [ ] **Step 3: Implement `ZipWriter` (test support), `Inflate`, `ZipArchive`**

Reader: locate the end-of-central-directory record by scanning backwards for `0x06054b50` within the last 64 KiB + 22 bytes; if the entry count or offsets are `0xFFFF`/`0xFFFFFFFF`, or a zip64 EOCD locator `0x07064b50` precedes it, throw `.unsupported`. Parse central directory headers (`0x02014b50`); flag bit 0 set → `.unsupported`; method not 0 or 8 → `.unsupported`. For each file entry, read the local header (`0x04034b50`) to find the data start (header + name length + extra length), read `compressedSize` bytes from the central directory values (valid even with data descriptors), inflate for method 8, and write to `directory.appending(path: name).standardizedFileURL` only if its path has `directory.path` as prefix. Use `FileHandle` reads per entry so a large archive is never fully loaded.

- [ ] **Step 4: Run tests to verify they pass**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

`feat(source): read stored and deflate zips on Compression, reject zip64 and encrypted`

---

### Task 4: Cover rendering

**Files:**
- Create: `app/FolioCore/Sources/FolioCore/Import/CoverImage.swift`
- Create: `app/FolioCore/Tests/FolioCoreTests/Support/ImageFixtures.swift`
- Test: `app/FolioCore/Tests/FolioCoreTests/CoverImageTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum CoverImage {
      public static let maxPixelSize = 600
      public static let fileName = "cover.jpg"
      /// Renders `page` downsampled to at most `maxPixelSize` on its longer side as JPEG at `destination`.
      /// Throws `CoverImageError.undecodable` when ImageIO cannot read the Page.
      public static func render(page: URL, to destination: URL) throws(CoverImageError)
  }
  public enum CoverImageError: Error, Equatable { case undecodable }
  ```
  Test support: `enum ImageFixtures { static func png(width: Int, height: Int, at url: URL) throws }` drawing a solid colour with CoreGraphics and writing via `CGImageDestination`.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite("Cover rendering")
struct CoverImageTests {
    @Test("downsamples to 600 on the long side, keeping aspect") func downsample() throws {
        /* png 1200x1800 → render → CGImageSource reports 400x600 */
    }
    @Test("leaves small Pages at their size") func small() throws { /* 300x450 → 300x450 */ }
    @Test("undecodable Page throws") func garbage() throws { /* write bytes "nope" as x.jpg → .undecodable */ }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path app/FolioCore -Xswiftc -warnings-as-errors --filter CoverImageTests`
Expected: compile failure.

- [ ] **Step 3: Implement with `CGImageSourceCreateThumbnailAtIndex`** using `kCGImageSourceCreateThumbnailFromImageAlways`, `kCGImageSourceThumbnailMaxPixelSize = 600`, `kCGImageSourceCreateThumbnailWithTransform = true`; write with `CGImageDestinationCreateWithURL(..., UTType.jpeg.identifier, ...)` at quality 0.85.

- [ ] **Step 4: Run tests to verify they pass**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

`feat(import): render the Cover with ImageIO`

---

### Task 5: Source access and storage capacity ports

**Files:**
- Create: `app/FolioCore/Sources/FolioCore/Source/SourceAccess.swift`
- Create: `app/FolioCore/Sources/FolioCore/Import/StorageCapacity.swift`
- Test: `app/FolioCore/Tests/FolioCoreTests/SourceAccessTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum SourceAccessError: Error, Equatable { case unavailable, notDownloaded }
  public protocol SourceAccess: Sendable {
      /// Bookmark for a URL the user just picked (while access is still granted by the picker).
      func bookmark(for url: URL) throws(SourceAccessError) -> Data
      /// Resolves a bookmark, ensures the item is downloaded, and runs `body` with access held.
      func withAccess<T: Sendable>(to bookmark: Data, _ body: @Sendable (URL) async throws -> T) async throws -> T
  }
  public struct InMemorySourceAccess: SourceAccess {   // test double: bookmark is the UTF-8 path
      public var unavailable: Set<String> = []          // paths that should fail as .unavailable
      public init()
  }
  public protocol StorageCapacity: Sendable { func availableBytes(at url: URL) throws -> Int64 }
  public struct VolumeStorageCapacity: StorageCapacity { public init() }   // volumeAvailableCapacityForImportantUsage
  public struct FixedStorageCapacity: StorageCapacity { public var bytes: Int64; public init(bytes: Int64) }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
@Suite("Source access")
struct SourceAccessTests {
    @Test("in-memory bookmark roundtrips to the same URL") func roundtrip() async throws {
        let access = InMemorySourceAccess()
        let url = URL(fileURLWithPath: "/tmp/x/Chapter 01")
        let data = try access.bookmark(for: url)
        let seen = try await access.withAccess(to: data) { $0 }
        #expect(seen.path == url.path)
    }
    @Test("unavailable paths throw .unavailable") func unavailable() async throws { /* set unavailable, expect throws SourceAccessError.unavailable */ }
    @Test("volume capacity reports a positive number for the temp directory") func capacity() throws {
        #expect(try VolumeStorageCapacity().availableBytes(at: FileManager.default.temporaryDirectory) > 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path app/FolioCore -Xswiftc -warnings-as-errors --filter SourceAccessTests`
Expected: compile failure.

- [ ] **Step 3: Implement the protocols and the two simple implementations.**

- [ ] **Step 4: Run tests to verify they pass.** Expected: PASS.

- [ ] **Step 5: Commit**

`feat(import): add SourceAccess and StorageCapacity ports with test doubles`

---

### Task 6: Import pipeline

**Files:**
- Create: `app/FolioCore/Sources/FolioCore/Import/ImportPipeline.swift`
- Test: `app/FolioCore/Tests/FolioCoreTests/ImportPipelineTests.swift`

**Interfaces:**
- Consumes: `SourceScanner`, `ZipArchive`, `CoverImage`, `StorageCapacity`, `Book`, `Page`, `ImportFailureReason`.
- Produces:
  ```swift
  public struct ImportFailure: Error, Equatable { public let reason: ImportFailureReason }
  public struct ImportPipeline: Sendable {
      public init(booksDirectory: URL, storage: StorageCapacity = VolumeStorageCapacity(), fileManager: FileManager = .default)
      /// Staging lives at `<booksDirectory>/.staging/<bookID>`; the final folder is `<booksDirectory>/<bookID>`.
      /// `progress` receives (pagesDone, pagesTotal), first call with (0, total).
      /// On any throw, including `CancellationError`, the staging folder is gone and no final folder exists.
      public func run(source: URL, bookID: BookID, title: String, importedAt: Date = .now,
                      progress: @Sendable (Int, Int) async -> Void) async throws -> Book
      /// Deletes every folder under `.staging`.
      public func removeAllStaging() throws
  }
  ```
  Final folder layout: `<bookID>/pages/0001.jpg, 0002.png …` (zero-padded index + original extension, lowercased) and `<bookID>/cover.jpg`. `Page.fileName` is the renamed file name.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite("Import pipeline")
struct ImportPipelineTests {
    @Test("folder Source becomes a Book with ordered renamed Pages and a Cover") func folder() async throws {
        /* fixtures: "b.jpg","a.png" real images via ImageFixtures; run; expect pages == ["0001.png","0002.jpg"], cover.jpg exists, no .staging/<id> */
    }
    @Test("zip Source is expanded and imported like a folder") func zip() async throws { /* ZipWriter with two images; same expectations */ }
    @Test(".ZIP in capitals is treated as a zip") func upperZip() async throws
    @Test("no images fails with noImagesFound and leaves nothing") func noImages() async throws { /* folder with notes.txt; #expect(throws: ImportFailure(reason: .noImagesFound)); no folders under booksDirectory */ }
    @Test("garbage zip fails with unreadableZip") func unreadable() async throws
    @Test("zip64 fails with unsupportedZip") func unsupported() async throws
    @Test("insufficient storage fails before copying") func storage() async throws { /* FixedStorageCapacity(bytes: 1); expect .notEnoughStorage; no .staging folder created */ }
    @Test("cancellation leaves nothing behind") func cancel() async throws {
        /* 50 images; progress handler cancels the enclosing Task after pagesDone == 5; expect CancellationError; booksDirectory contains no folders */
    }
    @Test("progress starts at zero and ends at total") func progress() async throws { /* collect calls; first == (0,n), last == (n,n) */ }
    @Test("removeAllStaging clears leftovers") func staging() async throws
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path app/FolioCore -Xswiftc -warnings-as-errors --filter ImportPipelineTests`
Expected: compile failure.

- [ ] **Step 3: Implement `ImportPipeline.run`**

Order of work: if `source.pathExtension.lowercased() == "zip"`, open `ZipArchive` (map `.unreadable`/`.unsupported` to failures) and extract into `<staging>/expanded`; scan Pages with `SourceScanner` (empty → `.noImagesFound`); sum file sizes and compare with `storage.availableBytes(at: booksDirectory)` (less → `.notEnoughStorage`); copy Pages one by one into `<staging>/pages` with their new names, calling `progress` and `Task.checkCancellation()` after each; render the Cover from the first Page; `moveItem` staging → final in one call; return the Book. Wrap in `do/catch` that removes the staging folder before rethrowing. For the storage check on a zip, the check happens before extraction using the entries' `uncompressedSize` sum.

- [ ] **Step 4: Run tests to verify they pass.** Expected: PASS.

- [ ] **Step 5: Commit**

`feat(import): atomic ImportPipeline from Source to Book folder`

---

### Task 7: Library actor: operations, scheduler, events, recovery

**Files:**
- Create: `app/FolioCore/Sources/FolioCore/Library/LibraryItem.swift`
- Create: `app/FolioCore/Sources/FolioCore/Library/Library.swift`
- Test: `app/FolioCore/Tests/FolioCoreTests/LibraryTests.swift`

**Interfaces:**
- Consumes: repositories, `ImportPipeline`, `SourceAccess`, `LibraryEvent`.
- Produces:
  ```swift
  public enum LibraryItem: Identifiable, Hashable, Sendable {
      case book(Book), importRecord(Import)
      public var id: String   // "book:<uuid>" or "import:<uuid>"
  }
  extension Array where Element == LibraryItem {
      /// In Progress first, then Queued by createdAt, then Failed by createdAt, then Books in Library order.
      public func inLibraryOrder() -> [LibraryItem]
  }
  public actor Library {
      public init(books: any BookRepository, imports: any ImportRepository,
                  pipeline: ImportPipeline, sourceAccess: any SourceAccess, now: @Sendable () -> Date = { .now })
      public nonisolated let events: AsyncStream<LibraryEvent>
      /// Deletes staging, returns In Progress Imports to Queued, removes Book records without folders and folders without records, then starts the scheduler.
      public func start() async throws
      public func items() async throws -> [LibraryItem]
      public func createImport(from pickedURL: URL) async throws -> ImportID   // bookmark, Title, add Queued, emit importQueued, schedule
      public func cancelImport(id: ImportID) async throws                     // Queued or In Progress → Failed(.cancelled)
      public func retryImport(id: ImportID) async throws                      // Failed → Queued, emit importQueued, schedule
      public func removeImport(id: ImportID) async throws                     // Failed only; remove record, emit importRemoved
      public func rename(bookID: BookID, to title: String) async throws       // trims; empty → LibraryError.emptyTitle
      public func open(bookID: BookID) async throws                           // lastOpenedAt = now, emit bookOpened
      public func removeBook(id: BookID) async throws                         // delete folder then record, emit bookRemoved
  }
  public enum LibraryError: Error, Equatable { case emptyTitle, notFound, invalidStatus }
  ```
  Scheduler: a private `Task` started by `start()` and re-kicked after every Import ends; when no Import is In Progress it takes the oldest Queued, sets In Progress, emits `importStarted` once the total is known (first progress call), runs `pipeline.run` inside `sourceAccess.withAccess`, then on success adds the Book, marks the Import Completed with `bookID`, emits `importCompleted`; on `ImportFailure`, `SourceAccessError` (`.unavailable → .sourceUnavailable`, `.notDownloaded → .sourceNotDownloaded`), or `CancellationError` (→ `.cancelled`) marks Failed and emits `importFailed`. `cancelImport` on the In Progress one cancels the running `Task`.

- [ ] **Step 1: Write the failing tests**

Use `InMemory*` repositories, `InMemorySourceAccess`, a `TemporaryDirectory` as the Books directory, and image fixtures. Collect events with a helper that drains `library.events` into an array until a predicate matches, with a 5 s timeout.

```swift
@Suite("Library")
struct LibraryTests {
    @Test("createImport queues, then completes into a Book") func happyPath() async throws {
        /* events contain importQueued, importStarted(total 2), importProgressed…, importCompleted; items() == [.book]; imports(status: .completed).count == 1 with bookID */
    }
    @Test("two Imports run serially, never both In Progress") func serial() async throws {
        /* create two; while draining events assert imports(status: .inProgress).count <= 1 at each event; both complete */
    }
    @Test("failure records reason and keeps the Import") func failure() async throws { /* folder with no images → importFailed(.noImagesFound); items() == [.importRecord(failed)] */ }
    @Test("retry re-queues under the same id and can complete") func retry() async throws { /* fail, then add an image to the folder, retry; same ImportID completes */ }
    @Test("cancel while In Progress fails with cancelled and leaves no Book") func cancel() async throws
    @Test("removeImport only works on Failed") func removeImport() async throws { /* Queued → LibraryError.invalidStatus; Failed → removed + importRemoved */ }
    @Test("rename rejects empty Title") func renameEmpty() async throws
    @Test("open sets lastOpenedAt and emits bookOpened") func open() async throws
    @Test("removeBook deletes folder and record") func removeBook() async throws
    @Test("start returns In Progress to Queued and runs it") func recovery() async throws {
        /* pre-seed an Import with status .inProgress and a valid bookmark; start(); expect importCompleted */
    }
    @Test("start removes Book records without folders and folders without records") func reconcile() async throws
    @Test("items are ordered In Progress, Queued, Failed, then Books") func itemOrder() async throws
    @Test("unavailable Source fails with sourceUnavailable") func unavailable() async throws
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path app/FolioCore -Xswiftc -warnings-as-errors --filter LibraryTests`
Expected: compile failure.

- [ ] **Step 3: Implement `LibraryItem` and `Library`** as specified. Events: `AsyncStream.makeStream(of: LibraryEvent.self, bufferingPolicy: .unbounded)` created in `init`, continuation stored on the actor.

- [ ] **Step 4: Run the whole package suite.** Run: `swift test --package-path app/FolioCore -Xswiftc -warnings-as-errors`. Expected: PASS.

- [ ] **Step 5: Commit**

`feat(library): Library actor with serial Import scheduler, events, and launch recovery`

---

### Task 8: SwiftData repositories and storage location

**Files:**
- Create: `app/Folio/Persistence/BookModel.swift`, `app/Folio/Persistence/ImportModel.swift`
- Create: `app/Folio/Persistence/SwiftDataBookRepository.swift`, `app/Folio/Persistence/SwiftDataImportRepository.swift`
- Create: `app/Folio/Persistence/LibraryStorage.swift`
- Test: `app/FolioTests/SwiftDataRepositoriesTests.swift`

**Interfaces:**
- Consumes: `Book`, `Import`, repository protocols, `Array.inLibraryOrder()`.
- Produces:
  ```swift
  @Model final class BookModel { @Attribute(.unique) var id: UUID; var title: String; var folderName: String; var pageFileNames: [String]; var coverFileName: String; var importedAt: Date; var lastOpenedAt: Date?; var readingPosition: Int?; init(_ book: Book); var book: Book }
  @Model final class ImportModel { @Attribute(.unique) var id: UUID; var status: String; var sourceBookmark: Data; var sourceName: String; var title: String; var pagesDone: Int; var pagesTotal: Int?; var failureReason: String?; var bookID: UUID?; var createdAt: Date; var finishedAt: Date?; init(_ record: Import); var record: Import }
  @ModelActor actor SwiftDataBookRepository: BookRepository { }
  @ModelActor actor SwiftDataImportRepository: ImportRepository { }
  enum LibraryStorage {
      /// `<Application Support>/<bundle id>/Books`, created if needed and marked `isExcludedFromBackup = true`.
      static func booksDirectory() throws -> URL
      /// Container whose store file is `<booksDirectory>/Library.store`.
      static func makeContainer(inMemory: Bool = false) throws -> ModelContainer
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
@Suite("SwiftData repositories")
@MainActor struct SwiftDataRepositoriesTests {
    @Test("Book roundtrips with explicit Page order") func bookRoundtrip() async throws {
        /* container inMemory; add Book with pages ["0002.jpg","0001.jpg"] (deliberately not sorted); fetch; pages equal in that order */
    }
    @Test("allBooks uses Library order") func order() async throws
    @Test("Import roundtrips status, reason and bookID") func importRoundtrip() async throws
    @Test("imports(status:) filters") func filter() async throws
    @Test("booksDirectory is excluded from backup") func backupExclusion() throws {
        let url = try LibraryStorage.booksDirectory()
        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./scripts/test.sh macos`
Expected: compile failure in FolioTests.

- [ ] **Step 3: Implement the models, repositories, and `LibraryStorage`.** Status and reason are stored as the enums' `rawValue` strings.

- [ ] **Step 4: Run tests to verify they pass.** Run: `./scripts/test.sh macos`. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

`feat(persistence): SwiftData repositories and backup-excluded Books directory`

---

### Task 9: File-based Source access

**Files:**
- Create: `app/Folio/Persistence/FileSourceAccess.swift`
- Test: `app/FolioTests/FileSourceAccessTests.swift`

**Interfaces:**
- Produces: `struct FileSourceAccess: SourceAccess { init() }`. Bookmark creation uses `.withSecurityScope` on macOS and default options on iOS (`#if os(macOS)`). `withAccess` resolves with the matching `.withSecurityScope` resolution option on macOS, calls `startAccessingSecurityScopedResource()` and stops in `defer`, checks `URLResourceValues.ubiquitousItemDownloadingStatus`; if not `.current`, calls `FileManager.startDownloadingUbiquitousItem` and polls up to 60 s, throwing `.notDownloaded` on timeout; a bookmark that fails to resolve or is stale throws `.unavailable`.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite("File source access")
struct FileSourceAccessTests {
    @Test("bookmark to a temp folder resolves to the same folder") func roundtrip() async throws {
        /* create temp dir; bookmark; withAccess returns URL with same standardized path */
    }
    @Test("bookmark to a deleted folder is unavailable") func deleted() async throws {
        /* bookmark, delete folder, expect SourceAccessError.unavailable */
    }
}
```

- [ ] **Step 2: Run tests to verify they fail.** Run: `./scripts/test.sh macos`. Expected: compile failure.

- [ ] **Step 3: Implement `FileSourceAccess`.**

- [ ] **Step 4: Run tests on both platforms.** Run: `./scripts/test.sh`. Expected: `** TEST SUCCEEDED **` for ios and macos.

- [ ] **Step 5: Commit**

`feat(persistence): FileSourceAccess with security-scoped bookmarks`

---

### Task 10: LibraryModel

**Files:**
- Create: `app/Folio/Library/LibraryModel.swift`
- Test: `app/FolioTests/LibraryModelTests.swift`

**Interfaces:**
- Consumes: `Library`, `LibraryItem`, `LibraryEvent`.
- Produces:
  ```swift
  @Observable @MainActor final class LibraryModel {
      struct FailureAlert: Identifiable, Equatable { let id: ImportID; let sourceName: String; let reason: ImportFailureReason }
      private(set) var items: [LibraryItem] = []
      private(set) var liveProgress: [ImportID: (done: Int, total: Int)] = [:]
      var failureAlert: FailureAlert?
      var isLoaded = false
      init(library: Library)
      func start() async            // library.start(), reload, then consume events for the lifetime of the model
      func reload() async           // items = try await library.items()
      func importSource(_ url: URL) async
      func cancelImport(_ id: ImportID) async
      func retryImport(_ id: ImportID) async
      func removeImport(_ id: ImportID) async
      func rename(_ id: BookID, to title: String) async
      func open(_ id: BookID) async        // records open; does NOT reload (order refreshes on next appear)
      func removeBook(_ id: BookID) async
      func coverURL(for book: Book) -> URL
  }
  ```
  Event handling: `importProgressed` updates `liveProgress` only; `importQueued`, `importStarted`, `importCompleted`, `importRemoved`, `bookRenamed`, `bookRemoved` reload; `importFailed` reloads and sets `failureAlert`; `bookOpened` does nothing. Errors from Library calls are logged with `AppLog.library` (add that category to `Logging.swift`).

- [ ] **Step 1: Write the failing tests**

```swift
@Suite("LibraryModel")
@MainActor struct LibraryModelTests {
    @Test("importing a folder ends with one Book item") func importFlow() async throws
    @Test("a failing Import sets the failure alert and keeps the Import item") func failure() async throws
    @Test("open does not reorder items until reload") func openNoReorder() async throws
}
```
Build the `Library` with in-memory repositories, `InMemorySourceAccess`, and a temp Books directory, as in Task 7. Await by polling `model.items` with a 5 s deadline.

- [ ] **Step 2: Run tests to verify they fail.** Run: `./scripts/test.sh macos`. Expected: compile failure.

- [ ] **Step 3: Implement `LibraryModel` and add `AppLog.library`.**

- [ ] **Step 4: Run tests to verify they pass.** Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

`feat(library): LibraryModel bridging Library events to SwiftUI state`

---

### Task 11: Library screen

**Files:**
- Create: `app/Folio/Library/LibraryView.swift`, `app/Folio/Library/BookCard.swift`, `app/Folio/Library/ImportCard.swift`, `app/Folio/Library/LibraryEmptyView.swift`, `app/Folio/Library/CoverView.swift`
- Modify: `app/Folio/FolioApp.swift`
- Delete: `app/Folio/ContentView.swift`
- Modify: `app/Folio/Localizable.xcstrings` (strings are added automatically by `SWIFT_EMIT_LOC_STRINGS` on build)

**Interfaces:**
- Consumes: `LibraryModel`, `LibraryItem`, `Book`, `Import`.
- Produces: `struct LibraryView: View { init(model: LibraryModel) }`. `FolioApp` builds the real `Library` (SwiftData repositories from `LibraryStorage.makeContainer()`, `ImportPipeline(booksDirectory:)`, `FileSourceAccess()`), wraps it in a `LibraryModel`, and shows `NavigationStack { LibraryView(model:) }` with `.task { await model.start() }`.

UI copy (exact, via `String(localized:)`):
- Navigation title: `Library`. Import button label: `Import`, system image `plus`.
- Empty state: title `No Books yet`, body `Import a folder of images, or a zip of one, from Files.`, button `Import a Book`.
- Book second line: `%lld pages` when `readingPosition == nil`; `Page %lld of %lld` otherwise, with a 3 pt `ProgressView` bar beneath.
- Import card second line: In Progress `%lld of %lld` (or `Preparing…` before the total is known); Queued `Waiting`; Failed shows the reason text from a `ImportFailureReason.localizedDescription` extension in this file:
  `noImagesFound → "No images found"`, `unreadableZip → "This zip can't be read"`, `unsupportedZip → "This zip format isn't supported"`, `sourceNotDownloaded → "Not downloaded to this device"`, `notEnoughStorage → "Not enough storage"`, `sourceUnavailable → "The folder or zip is no longer available"`, `cancelled → "Cancelled"`.
- Context menus: Book → `Rename…`, `Delete Book` (destructive). In Progress/Queued Import → `Cancel Import`. Failed Import → `Retry`, `Remove`. A Failed card also shows a small `Retry` button over its placeholder Cover.
- Delete confirmation: `Delete “%@”?`, message `Its pages will be removed from Folio.`, buttons `Delete` (destructive) and `Cancel`.
- Rename: an alert with a text field, buttons `Save` and `Cancel`; empty text keeps `Save` disabled.
- Failure alert: title `Couldn't Import “%@”`, message is the reason text, button `OK`.

Layout: `ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 12)], spacing: 16) }` with 16 pt horizontal padding; cards are `aspectRatio(2/3)` Covers with `clipShape(.rect(cornerRadius: 6))` and a small shadow; Title `.subheadline.weight(.semibold)` one line truncated; second line `.caption` secondary. Tap on a Book calls `model.open`. `.fileImporter(isPresented:allowedContentTypes: [.folder, .zip], allowsMultipleSelection: false)`; on success call `url.startAccessingSecurityScopedResource()`, `await model.importSource(url)`, then stop accessing. The grid reloads in `.onAppear` and `.scenePhase == .active`.

- [ ] **Step 1: Build the views and wire `FolioApp`.** There is no unit test for layout; the check is the gate.

- [ ] **Step 2: Run the gate.** Run: `./scripts/verify.sh`. Expected: green on ios and macos; `build/launch-ios.png` and `build/launch-macos.png` show the empty state.

- [ ] **Step 3: Manual check on Mac** (the simulator's Files app has no scriptable way to add a folder): put a folder with two PNGs in `~/Downloads`, run `./scripts/run.sh macos`, Import it, confirm a Book card with its Cover and `2 pages` appears, rename it, delete it. Record what you saw in the commit body.

- [ ] **Step 4: Commit**

`feat(library): Library screen with Import, Book and Import cards, rename and delete`

---

### Task 12: Mac commands, drop target, selection, Delete key

**Files:**
- Create: `app/Folio/Library/LibraryCommands.swift`, `app/Folio/Library/LibraryDropTarget.swift`
- Modify: `app/Folio/Library/LibraryView.swift`, `app/Folio/FolioApp.swift`

**Interfaces:**
- Produces (all under `#if os(macOS)`): `struct LibraryCommands: Commands` adding `File → Import…` with `.keyboardShortcut("i", modifiers: .command)` that sets a `FocusedValue`-published `Binding<Bool>` the view uses to present its `fileImporter`; a toolbar `Import…` button; `.dropDestination(for: URL.self)` on the grid accepting a folder or `.zip` URL and calling `model.importSource`; a `@State var selection: BookID?` set on single click, double click calls `model.open`, `.onDeleteCommand` presents the delete confirmation for the selection.

- [ ] **Step 1: Implement.**

- [ ] **Step 2: Run the gate.** Run: `./scripts/verify.sh macos`. Expected: green.

- [ ] **Step 3: Manual check on Mac**: ⌘I opens the picker; dragging a zip onto the window creates an Import that completes; clicking a Book selects it and Delete asks for confirmation; double-click records open (visible as the card moving to the front after switching away and back).

- [ ] **Step 4: Commit**

`feat(library): Mac import command, drag-and-drop, selection and Delete key`

---

### Task 13: iPad Select mode

**Files:**
- Create: `app/Folio/Library/LibrarySelectionBar.swift`
- Modify: `app/Folio/Library/LibraryView.swift`

**Interfaces:**
- Produces (`#if os(iOS)`, shown only when `horizontalSizeClass == .regular`): a `Select` / `Done` toolbar toggle (`EditMode`), checkmarks on selected Book cards, a bottom bar with `Delete (%lld)` that presents one confirmation `Delete %lld Books?` and then calls `model.removeBook` for each.

- [ ] **Step 1: Implement.**

- [ ] **Step 2: Run the gate.** Run: `SIMULATOR="iPad Pro 11-inch (M5)" ./scripts/verify.sh ios` (or the UDID of an iPad simulator from `xcrun simctl list devices available`). Expected: green.

- [ ] **Step 3: Commit**

`feat(library): iPad Select mode for multi-delete`

---

### Task 14: Documentation and gate

**Files:**
- Modify: `CLAUDE.md` (Architecture: describe FolioCore `Domain/Source/Import/Library` and app `Persistence/Library` folders in two short paragraphs; Conventions: `AppLog.library`)
- Modify: `DECISIONS.md` (append: Import persisted at creation and scheduled serially; SwiftData store inside the Books directory; zip reader scope)
- Create: `docs/logs/2026-11-08-03-library-and-import-implementation.md` per the `structured-commit` log format, recording what the zip reader and Compression framework taught, any simulator or SwiftData gotchas, and the final test counts.

- [ ] **Step 1: Update the three documents.**

- [ ] **Step 2: Run the full gate.** Run: `./scripts/verify.sh`. Expected: green on both platforms.

- [ ] **Step 3: Commit**

`docs(library): record architecture, decisions, and implementation log for the Library slice`
