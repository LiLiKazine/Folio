# Reading Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Book can be read Vertical, as one width-fitted strip of touching Pages, remembers that choice, and keeps its Reading Position and memory budget while doing so.

**Architecture:** `ReadingMode` joins the Book value and the Library actor gets `chooseReadingMode`, announced as `ReadingModeChanged`. The store moves to schema V2 with one optional column. On screen, `ReadingView` hosts both modes; a new `VerticalStripView` lays Pages out at heights fixed from their pixel sizes, derives the current Page from scroll geometry with a pure rule, and shows Pages as slices from a budgeted `SlicedPageCache` that decodes one Page at a time at screen width.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, SwiftData (`VersionedSchema`, lightweight migration), ImageIO, CoreGraphics, Swift Testing. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-09-reading-mode-design.md` (glossary `CONTEXT.md`; builds on `docs/superpowers/specs/2026-11-08-reading-design.md`)

## Global Constraints

- `CONTEXT.md` terms exactly; never the `_Avoid_` words (for Reading Mode: "layout", "view mode", "scroll mode", "webtoon"; for Page: "image", "file"; for Reading Position: "progress"). "Strip", "slice", "budget" are mechanisms defined in the spec and the decision log.
- Swift 6 strict concurrency, warnings as errors; Swift Testing only; OSLog only (`AppLog.reading` for the screen and decoders, `AppLog.library` for the model); SwiftUI only unless the spec's zoom exception is invoked and recorded in `DECISIONS.md`.
- Scroll mechanics rest on documented SwiftUI behaviour, quoted in the implementation log. No timers, delays or polling.
- Pages are never decoded wider than their own pixels. Vertical decode width is `min(pageWidth, screenWidthPixels)`, lowered to fit the per-Page budget: 96 MB on iOS, 256 MB on macOS; cache budget three per-Page budgets; the Page at the top and the next are never released.
- Failed `chooseReadingMode` saves are log-only with the comment the Visible Failures rule requires, pointing at the spec.
- Strings in `Localizable.xcstrings`, synced from both platforms' stringsdata as `CLAUDE.md` says: "Reading Mode", "Page by Page", "Vertical".
- Commands: `swift test --package-path app/FolioCore -Xswiftc -warnings-as-errors` for FolioCore; `./scripts/test.sh macos` to iterate on the app; `./scripts/verify.sh` as the gate; `./scripts/format.sh --check` clean. Commit after each task in the structured format with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01LmeQ4kF6jaBLLT9tw3CStM`. Work on branch `feature/reading-mode`.

## Review Focus

1. A Book whose Pages are all shorter than the screen (landscape photos on an upright iPhone): opening in Vertical must land on the Reading Position's Page and the counter must read that Page, not a later one. Pinned by the `pageAtTop` tests in Task 3 (short Pages case) and the owner's manual check in Task 5.
2. A Page file that is not an image inside a Vertical Book: its slot is a square the strip's width with the placeholder; the strip does not jump when it is reached. Pinned in Task 3 (`pixelSize` nil → square) and Task 3's geometry test.
3. A Book of one Page in Vertical: the slider is disabled, the strip is that one Page, `pageAtTop` is 0 at every offset. Pinned in Task 3.
4. A Page wider than the screen with very large height (3000 × 40,000): the width rule must lower the decode width so the Page fits the budget; slices must each be under the GPU bound. Pinned in Task 3 (`decodeWidth` and `slice` tests).
5. A store written by the current build (V1) opened by this build: every Book reads Page by Page, nothing is lost. Pinned in Task 2.

---

## File Structure

- Create `app/FolioCore/Sources/FolioCore/Domain/ReadingMode.swift`.
- Modify `app/FolioCore/Sources/FolioCore/Domain/Book.swift`, `Domain/LibraryEvent.swift`, `Library/LibraryError.swift`, `Library/Library.swift`.
- Modify `app/FolioCore/Tests/FolioCoreTests/LibraryTests.swift`, `LibraryErrorTests.swift`.
- Modify `app/Folio/Persistence/BookModel.swift`, `FolioSchema.swift`, `LibraryStorage.swift`; test `app/FolioTests/SwiftDataRepositoriesTests.swift`.
- Modify `app/Folio/Library/LibraryModel.swift`; test `app/FolioTests/LibraryModelTests.swift`.
- Create `app/Folio/Reading/StripGeometry.swift` (pure: frames and the top-of-screen rule), `app/Folio/Reading/SlicedPage.swift` (pure width rule, slicing), `app/Folio/Reading/SlicedPageCache.swift` (actor), `app/Folio/Reading/VerticalStripView.swift`.
- Modify `app/Folio/Reading/PageImage.swift` (`pixelSize`), `ReadingView.swift`, `ReadingChrome.swift`.
- Tests: create `app/FolioTests/StripGeometryTests.swift`, `SlicedPageTests.swift`, `SlicedPageCacheTests.swift`; modify `PageImageTests.swift`, `ReadingViewTests.swift`.
- Docs: `DECISIONS.md`, `CLAUDE.md` (Reading paragraph), `docs/logs/2026-11-09-02-reading-mode-implementation.md`, update `docs/logs/2026-11-09-01-reading-mode-design.md` Status and Commits.

---

### Task 1: Reading Mode in FolioCore

**Files:** Create `Domain/ReadingMode.swift`; Modify `Domain/Book.swift`, `Domain/LibraryEvent.swift`, `Library/LibraryError.swift`, `Library/Library.swift`; Test `LibraryTests.swift`, `LibraryErrorTests.swift`.

**Interfaces (produces):**
```swift
public enum ReadingMode: String, Codable, Sendable, CaseIterable { case pageByPage, vertical }
// Book
public var readingMode: ReadingMode   // init parameter `readingMode: ReadingMode = .pageByPage`, last
// LibraryEvent
case readingModeChanged(BookID, mode: ReadingMode)
// LibraryOperation
case chooseReadingMode = "Choose Reading Mode"
// Library
public func chooseReadingMode(bookID: BookID, _ mode: ReadingMode) async throws(LibraryError)
```
`Book`'s `Codable` must decode a payload without `readingMode` as `.pageByPage` (custom `init(from:)` with `decodeIfPresent`, or equivalent).

- [ ] **Step 1: Failing tests in `LibraryTests.swift`** — `chooseReadingMode` stores `.vertical` and emits `.readingModeChanged(id, mode: .vertical)`; choosing the stored mode again emits nothing and performs no repository update (use the existing fixture's event collection and the in-memory repository's call record if it has one, otherwise assert only on events); unknown Book throws `.notFound(.chooseReadingMode)`; a Book JSON without `readingMode` decodes as `.pageByPage`. In `LibraryErrorTests.swift`, add `.chooseReadingMode` to the `switch` (`try await library.chooseReadingMode(bookID: book.id, .vertical)`) and `StorageCase(operation: .chooseReadingMode, store: .books, call: .update)`.
- [ ] **Step 2: Run** `swift test --package-path app/FolioCore -Xswiftc -warnings-as-errors` → compile failure.
- [ ] **Step 3: Implement** the interfaces above; `chooseReadingMode` mirrors `turnPage` through `storageGuard(.chooseReadingMode)`.
- [ ] **Step 4: Run** → `Test run with N tests passed`.
- [ ] **Step 5: Commit** `feat(library): Books remember a Reading Mode; chooseReadingMode announces ReadingModeChanged`.

---

### Task 2: Persistence V2 and the model's log-only choose

**Files:** Modify `Persistence/BookModel.swift`, `Persistence/FolioSchema.swift`, `Persistence/LibraryStorage.swift`, `Library/LibraryModel.swift`; Test `SwiftDataRepositoriesTests.swift`, `LibraryModelTests.swift`.

**Interfaces:**
- Consumes Task 1.
- Produces `LibraryModel.chooseReadingMode(_ id: BookID, _ mode: ReadingMode) async` (never queues a Notice); `FolioSchemaV2` current, `FolioSchemaV1` frozen with copies of the V1 models inside the enum (`FolioSchemaV1.BookModel`, `FolioSchemaV1.ImportModel`), `FolioMigrationPlan.stages = [.lightweight(fromVersion: FolioSchemaV1.self, toVersion: FolioSchemaV2.self)]`; `LibraryStorage.makeContainer` builds its `Schema` from `FolioSchemaV2`.
- `BookModel.readingMode: String?`; `book` maps `ReadingMode(rawValue:) ?? .pageByPage`; `init`/`apply` write `book.readingMode.rawValue`.

- [ ] **Step 1: Failing tests** — in `SwiftDataRepositoriesTests`: `readingModeRoundtrips` (store `.vertical`, read back `.vertical`); `v1StoreOpensAsPageByPage`: build a container on disk with `Schema(versionedSchema: FolioSchemaV1.self)` at a temp URL, insert a `FolioSchemaV1.BookModel`, close it, open the same URL with `makeContainer`'s V2 path (factor a `makeContainer(at url: URL)` if needed), and assert one Book with `readingMode == .pageByPage`. In `LibraryModelTests`: `chooseReadingModeFailureQueuesNoNotice` using the failing-repository fixture the `turnPage` test uses; assert `notices.isEmpty` after the call returns.
- [ ] **Step 2: Run** `./scripts/test.sh macos` → failures.
- [ ] **Step 3: Implement.** `handle` adds `.readingModeChanged` to the `case .bookOpened, .readingPositionChanged:` line. The `catch` in `chooseReadingMode` carries: `// Log-only by the owner's ruling (Reading Mode design, "A failed Reading Mode save is log-only"): the switch itself visibly succeeded.`
- [ ] **Step 4: Run** `./scripts/test.sh macos` → `** TEST SUCCEEDED **`.
- [ ] **Step 5: Commit** `feat(persistence): schema V2 stores a Book's Reading Mode; the model chooses it log-only`.

---

### Task 3: Pure pieces for Vertical: geometry rule, pixel size, width rule, slicing, budgeted cache

**Files:** Create `Reading/StripGeometry.swift`, `Reading/SlicedPage.swift`, `Reading/SlicedPageCache.swift`; Modify `Reading/PageImage.swift`; Test `StripGeometryTests.swift`, `SlicedPageTests.swift`, `SlicedPageCacheTests.swift`, `PageImageTests.swift`.

**Interfaces (produces):**
```swift
struct StripGeometry: Equatable, Sendable {
    /// Heights in points at `width`; a nil pixel size is a square of `width`.
    init(pixelSizes: [CGSize?], width: CGFloat)
    var heights: [CGFloat]
    var tops: [CGFloat]            // prefix sums, tops[0] == 0
    var contentHeight: CGFloat
    /// The spec's rule: last Page with top <= offset; at the end (offset > 0 and offset + viewport >= contentHeight) the last Page; offset <= 0 → 0. Empty strip → 0. The `offset > 0` guard keeps a strip shorter than the screen on its first Page.
    func pageAtTop(offset: CGFloat, viewportHeight: CGFloat) -> Int
}
enum PageImage {
    static func pixelSize(url: URL) -> CGSize?     // CGImageSourceCopyPropertiesAtIndex, orientation applied (width/height swapped for EXIF 5–8)
}
enum SlicedPage {
    static let sliceMaxHeight = 2048               // pixels; under every GPU bound
    static func perPageBudget() -> Int             // 96 * 1024 * 1024 on iOS, 256 * 1024 * 1024 on macOS (#if os(macOS))
    /// min(pageWidth, screenWidth), lowered so width*height*4 <= budget keeping aspect; at least 1.
    static func decodeWidth(pageSize: CGSize, screenWidthPixels: Int, budget: Int) -> Int
    /// Decodes at `width` with ImageIO (kCGImageSourceThumbnailMaxPixelSize = the longer side at that width), then crops into slices of at most sliceMaxHeight rows; nil when undecodable.
    static func decode(url: URL, width: Int) -> [CGImage]?
    static func bytes(of slices: [CGImage]) -> Int // sum of bytesPerRow * height
}
actor SlicedPageCache {
    init(urls: [URL], screenWidthPixels: Int, perPageBudget: Int = SlicedPage.perPageBudget(), cacheBudget: Int? = nil /* default 3 × perPageBudget */)
    func slices(at index: Int) async -> [CGImage]?   // decodes if missing, one at a time (actor), honours Task.isCancelled like PageImageCache
    func retain(top: Int)                             // marks `top` and `top + 1` unreleasable; releases oldest-used others until bytes <= cacheBudget
    func prefetch(around index: Int)                  // decodes index-1 ... index+2 where present, then applies the budget
    private(set) var decodeCount: Int
}
```
`decodeWidth` uses `kCGImageSourceThumbnailMaxPixelSize` on the longer side: for a tall Page the longer side is the height, so pass `Int((Double(width) * pageSize.height / pageSize.width).rounded(.up))` when height ≥ width, else `width`.

- [ ] **Step 1: Failing tests.** `StripGeometryTests`: heights from `[CGSize(800, 1200), nil, CGSize(800, 400)]` at width 400 are `[600, 400, 200]`, tops `[0, 600, 1000]`, contentHeight 1200; `pageAtTop` cases over heights `[600, 400, 200]`, viewport 500: offset −20 → 0, 0 → 0, 599 → 0, 600 → 1, 999 → 1, 1000 → 2, 700 (end, since 700 + 500 ≥ 1200) → 2; short Pages: heights `[100, 100, 100, 100]`, viewport 500, offset 0 → 0 (strip shorter than the screen stays on its first Page), offset 1 → 3 (end); one Page → 0 at offsets −10, 0, 50; empty → 0. `PageImageTests`: `pixelSize` of a 64 × 96 PNG is (64, 96); of a text file is nil. `SlicedPageTests`: `decodeWidth(pageSize: (800, 12000), screen 1179, budget 96 MB)` → 800; `(3000, 40000)`, screen 1179, budget 96 MB → the largest w with w * (w * 40000 / 3000) * 4 ≤ budget (assert `w <= 1179` and `w * ceil(w*40000/3000) * 4 <= budget` and `(w+1)` violates); `decode` of a 64 × 5000 PNG at width 64 gives slices whose heights sum to 5000 and each ≤ 2048, widths all 64; text file → nil. `SlicedPageCacheTests` (PNG fixtures of 8 × 8, budget set tiny, e.g. perPage 1024, cache 2048): `slices(at:)` decodes once and reuses (decodeCount 1 after two calls); `retain(top: 0)` then `prefetch(around: 0)` keeps 0 and 1 and releases 2 when over budget (ask for 2 again → decodeCount increments); a cancelled task gets nil without decoding.
- [ ] **Step 2: Run** `./scripts/test.sh macos` → compile failure.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** → `** TEST SUCCEEDED **`.
- [ ] **Step 5: Commit** `feat(reading): strip geometry rule, pixel sizes, width rule, slices and a budgeted cache for Vertical`.

---

### Task 4: The Vertical strip on screen, the Reading Mode control, strings

**Files:** Create `Reading/VerticalStripView.swift`; Modify `Reading/ReadingView.swift`, `Reading/ReadingChrome.swift`, `Localizable.xcstrings`; Test `ReadingViewTests.swift`.

**Interfaces:**
- Consumes Tasks 1–3.
- `ReadingView` gains `@State private var mode: ReadingMode` seeded from `book.readingMode`; body shows `pager` when `.pageByPage`, `VerticalStripView(book:index:$index, cache:, geometry:, onTap:)` when `.vertical`. Choosing calls `mode = m` then `Task { await model.chooseReadingMode(book.id, m) }`; the `.id(mode)` on the content resets zoom (view state is recreated on switch).
- `VerticalStripView`: `ScrollView([.vertical, .horizontal])` (horizontal only scrolls when zoomed) over a `LazyVStack(spacing: 0)` of `ForEach(book.pages.indices)`; each row is a fixed frame `width × geometry.heights[i]` (times zoom) containing the Page's slices stacked (`VStack(spacing: 0)` of `Image(decorative:scale:)` resizable) or the placeholder; rows carry `.id(i)` and the stack `.scrollTargetLayout()`.
  - Current Page: `onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top }` → `geometry.pageAtTop(offset:viewportHeight: geometry.visibleRect.height)`; write to `index` only when different. Quote Apple's `onScrollGeometryChange` and `ScrollGeometry.contentOffset` descriptions in the log.
  - Programmatic jumps (`index` set from outside: slider, keys, switch, open): `ScrollViewProxy.scrollTo(index, anchor: .top)` from `onChange(of: index)` guarded by "not the Page the rule just reported", so the reader's own scroll is not fought. Quote `scrollTo(_:anchor:)`.
  - Zoom: the `PageView` technique (frame width × `liveScale`, `MagnifyGesture` + double tap), applied to the whole stack; `scrollDisabled(false)` always (vertical scrolling is the point); `defaultScrollAnchor(.center, for: .sizeChanges)` not used (anchor is the top Page).
  - Cache: `SlicedPageCache(urls:, screenWidthPixels: Int(width * displayScale))`, rebuilt when the width in pixels changes (the `decodeSize` step helper is for the pager; Vertical uses the exact width); on `index` change `retain(top: index)` then `prefetch(around: index)`. Pixel sizes are read once per Book on a background task into `geometry`; until known, each Page is a square of `width` (the geometry with all-nil sizes), so the strip exists at once.
- `ReadingChrome` or the toolbar gains a `Picker("Reading Mode", selection:)` with "Page by Page" and "Vertical", `.pickerStyle(.segmented)` on Mac toolbar and a `Menu` on iOS if the segmented control crowds the bar (builder's call).
- Mac keys: `.leftArrow`/`.rightArrow` keep calling `turn(by:)` in both modes.

- [ ] **Step 1: Unit tests in `ReadingViewTests`** — `startIndex` unchanged (already there); `startMode` is `book.readingMode` (add `static func startMode(for:)` if that is how the seed is expressed).
- [ ] **Step 2: Implement**, then add the three strings and sync the catalog from both platforms' stringsdata (`CLAUDE.md`), restoring compact `{}` entries.
- [ ] **Step 3: Gate** `./scripts/verify.sh` green on both platforms; `grep -rn "layout\b\|webtoon\|scroll mode\|view mode" app/Folio/Reading app/FolioTests --include=*.swift -i` shows only Apple API names (`layout` must not appear in any identifier).
- [ ] **Step 4: Manual check (builder, Mac)** with `~/Downloads/FolioSamples/Sample Book`: switch to Vertical, scroll, counter follows the top Page; slider jumps land the Page at the top; close and reopen lands in Vertical on that Page; switch back shows the same Page. Record in the log.
- [ ] **Step 5: Commit** `feat(reading): Vertical Reading Mode as one strip of touching Pages, chosen from the chrome`.

---

### Task 5: Docs and the owner's check list

**Files:** Modify `DECISIONS.md`, `CLAUDE.md` (Reading paragraph: name `VerticalStripView`, `SlicedPageCache`), `docs/logs/2026-11-09-01-reading-mode-design.md` (Status → Implemented; Commits table); Create `docs/logs/2026-11-09-02-reading-mode-implementation.md`.

- [ ] **Step 1: Write the documents.** `DECISIONS.md` gets one dated section in plain language covering the six entries the spec lists ("Decision log entries this slice must add"), each mechanism defined before use. The implementation log follows the format of `docs/logs/2026-11-08-05-presentation-coordinator.md`: the Apple documentation quotes the scroll mechanics rest on, measured memory for a tall sample Page (make one: a 800 × 12,000 PNG via the test helper, dropped into a sample Book), and the owner's manual check list on Mac, iPhone, iPad: choose Vertical and scroll; counter and card agree; reopen lands in Vertical; a Book with short Pages opens on the right Page; a tall Page is sharp and the app stays responsive; switch back keeps the Page.
- [ ] **Step 2: Gate** `./scripts/verify.sh` green; `./scripts/format.sh --check` clean.
- [ ] **Step 3: Commit** `docs(reading): record the Reading Mode rulings and the owner's check list`.
