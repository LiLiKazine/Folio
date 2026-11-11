# Library Order Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The reader chooses a Sort (Recent, Title, Date Imported) and a Direction (Ascending, Descending) for the Library's Books, and the Library remembers the choice.

**Architecture:** `LibraryOrder` is a value in FolioCore with a pure ordering rule for Books. The `Library` actor owns it: it reads and saves it through a new `LibraryOrderRepository` port, orders `items()` by it, and announces `LibraryOrderChanged`. The app stores it as one row in the Library's SwiftData store (schema V3), `LibraryModel` exposes it and reloads on the event, and a toolbar menu plus a Mac View-menu submenu choose it.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, SwiftData (`VersionedSchema`, lightweight migration), Swift Testing. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-11-library-order-design.md` (glossary `CONTEXT.md`; builds on `docs/superpowers/specs/2026-11-08-library-and-import-design.md` and `2026-11-08-visible-failures-design.md`). Read it before any task.

## Global Constraints

- `CONTEXT.md` terms exactly: Library Order, Sort, Direction, Recent, Title, Date Imported, Ascending, Descending. Never the `_Avoid_` words: "category", "sort rule", "date added", "name", "arrangement", "ordering", "sorting", bare "order" for a Direction, "reverse". This covers code, tests, copy and commits.
- Swift 6 strict concurrency, warnings as errors; Swift Testing only; OSLog only (`AppLog.library`, `AppLog.persistence`); SwiftUI only.
- The starting Library Order is Recent, Descending (`LibraryOrder.initial`). A stored one this version does not recognise reads as `initial`.
- Descending is exactly Ascending reversed, for Books. Imports In Progress, then Queued, then Failed stay first, each by `createdAt` ascending, under every Library Order.
- Title is compared with `localizedStandardCompare`. Ties go to `importedAt`, then to the identifier's UUID string.
- A failed Choose Library Order save queues a Notice and changes nothing on screen. Choosing the Library Order already in force saves nothing and announces nothing.
- The menu has no heading that says "Order". Its copy is "Sort", "Sort By", "Recent", "Title", "Date Imported", "Ascending", "Descending".
- Opening a Book still does not reload the grid (`LibraryModel.open`).
- Designs rest on Apple's documentation, quoted in the implementation log; where it is silent, say what was observed. No timers, delays or guards around undocumented timing.
- No keystrokes or clicks are sent to the owner's Mac. iPhone and iPad checks run on a simulator; Mac checks go on the owner's check list.
- Commands: `swift test --package-path app/FolioCore -Xswiftc -warnings-as-errors` for FolioCore; `./scripts/test.sh macos` to iterate on the app; `./scripts/verify.sh` as the gate; `./scripts/format.sh --check` clean.
- Every task ends with every target compiling and its tests green. Commit after each task with the `structured-commit` skill, authored as LiLi, ending with `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01LmeQ4kF6jaBLLT9tw3CStM`. Work on branch `feature/library-order`, cut from `main` after the spec, the glossary change and this plan are committed there.

## Review Focus

1. A Library made by the current build (schema V2), opened by this build: every Book is there, in Recent, Descending, and no Library Order is stored. Pinned in Task 2 (`v2StoreOpensWithNoLibraryOrder`); the V1 test must still pass through both stages.
2. Titles that differ only by case or by a number's width ("vol 2", "Vol 3", "Vol 10"), and two Books with the same Title (one Source imported twice): the first sort as 2, 3, 10; the second pair keeps one fixed order across reloads and reverses with the Direction. Pinned in Task 1.
3. Ascending with Imports on screen, and Recent, Ascending with Books never opened: Imports stay first; a Book never opened sorts by its imported time. Pinned in Task 1.
4. The save fails: the Notice is "Couldn't Choose Library Order", `items` and `libraryOrder` are unchanged, and no event is announced. Pinned in Task 3 (Library and `LibraryModel`).
5. A stored Sort or Direction that names no case (a store written by a later version): it reads as Recent, Descending and the Library opens. Pinned in Task 2.

---

## File Structure

- Create `app/FolioCore/Sources/FolioCore/Domain/LibraryOrder.swift`: the values and the ordering rule for Books.
- Modify `app/FolioCore/Sources/FolioCore/Domain/Repositories.swift`, `InMemoryRepositories.swift`, `FailingRepositories.swift`: the port and its two test implementations.
- Modify `app/FolioCore/Sources/FolioCore/Library/LibraryItem.swift`, `Library/Library.swift`, `Library/LibraryError.swift`, `Domain/LibraryEvent.swift`, `Domain/Book.swift`.
- Create `app/FolioCore/Tests/FolioCoreTests/LibraryOrderTests.swift`; modify `LibraryTests.swift`, `LibraryErrorTests.swift`, `InMemoryRepositoriesTests.swift`.
- Create `app/Folio/Persistence/LibraryOrderModel.swift`, `SwiftDataLibraryOrderRepository.swift`; modify `FolioSchema.swift`, `LibraryStorage.swift`, `SwiftDataBookRepository.swift`; test `app/FolioTests/SwiftDataRepositoriesTests.swift`.
- Modify `app/Folio/Library/LibraryModel.swift`, `app/Folio/FolioApp.swift`; test `app/FolioTests/LibraryModelTests.swift`, `NoticeTests.swift`.
- Create `app/Folio/Library/LibraryOrderMenu.swift`; modify `LibraryView.swift`, `LibraryWindow.swift`, `LibraryCommands.swift`, `Localizable.xcstrings`; test `app/FolioTests/LibraryOrderMenuTests.swift`.
- Docs: `DECISIONS.md`, `CLAUDE.md`, `docs/logs/2026-11-11-NN-library-order-implementation.md` (NN is the next free number for the day).

---

### Task 1: The Library Order value, its ordering rule and its port (FolioCore)

**Files:** Create `Domain/LibraryOrder.swift`, `Tests/.../LibraryOrderTests.swift`; Modify `Domain/Repositories.swift`, `Domain/InMemoryRepositories.swift`, `Domain/FailingRepositories.swift`, `Library/LibraryItem.swift`, `Library/Library.swift` (one call site); Test `LibraryTests.swift` (the items-order test's call).

**Interfaces (produces):**
```swift
public struct LibraryOrder: Equatable, Hashable, Sendable, Codable {
    public enum Sort: String, Codable, Sendable, CaseIterable { case recent, title, dateImported }
    public enum Direction: String, Codable, Sendable, CaseIterable { case ascending, descending }
    public var sort: Sort
    public var direction: Direction
    public init(sort: Sort, direction: Direction)
    /// Recent, Descending.
    public static let initial: LibraryOrder
}
extension Array where Element == Book {
    public func ordered(by order: LibraryOrder) -> [Book]
}
extension Array where Element == LibraryItem {
    public func inLibraryOrder(_ order: LibraryOrder) -> [LibraryItem]   // replaces inLibraryOrder()
}
public protocol LibraryOrderRepository: Sendable {
    /// The saved Library Order; nil when none was ever saved.
    func libraryOrder() async throws -> LibraryOrder?
    func save(_ order: LibraryOrder) async throws
}
public actor InMemoryLibraryOrderRepository: LibraryOrderRepository { public init() }
public actor FailingLibraryOrderRepository: LibraryOrderRepository {
    public init(base: InMemoryLibraryOrderRepository = InMemoryLibraryOrderRepository())
    public func fail(_ calls: Set<RepositoryCall>)
    public func succeed()
}
// RepositoryCall gains: libraryOrder, saveLibraryOrder
```
`[Book].inLibraryOrder()` stays for now; Task 3 removes it.

- [ ] **Step 1: Write the failing tests** in `LibraryOrderTests.swift` (`@Suite("Library Order")`). A helper `book(_ title: String, imported: TimeInterval, opened: TimeInterval? = nil, id: UUID = UUID()) -> Book` builds a Book with one Page. Tests, each asserting on `books.ordered(by:).map(\.title)` (or `.map(\.id)` where Titles repeat):

```swift
@Test("the starting Library Order is Recent, Descending")
func initial() { #expect(LibraryOrder.initial == LibraryOrder(sort: .recent, direction: .descending)) }

@Test("Recent orders by the last open, or the Import when never opened")
func recent() {
    let books = [book("A", imported: 10), book("B", imported: 30), book("C", imported: 20, opened: 40)]
    #expect(books.ordered(by: .init(sort: .recent, direction: .descending)).map(\.title) == ["C", "B", "A"])
    #expect(books.ordered(by: .init(sort: .recent, direction: .ascending)).map(\.title) == ["A", "B", "C"])
}

@Test("Title ignores case and counts numbers as numbers")
func title() {
    let books = [book("Vol 10", imported: 1), book("vol 2", imported: 2), book("Vol 3", imported: 3)]
    #expect(books.ordered(by: .init(sort: .title, direction: .ascending)).map(\.title) == ["vol 2", "Vol 3", "Vol 10"])
    #expect(books.ordered(by: .init(sort: .title, direction: .descending)).map(\.title) == ["Vol 10", "Vol 3", "vol 2"])
}

@Test("Date Imported ignores opens")
func dateImported() {
    let books = [book("A", imported: 10, opened: 99), book("B", imported: 30), book("C", imported: 20)]
    #expect(books.ordered(by: .init(sort: .dateImported, direction: .descending)).map(\.title) == ["B", "C", "A"])
    #expect(books.ordered(by: .init(sort: .dateImported, direction: .ascending)).map(\.title) == ["A", "C", "B"])
}

@Test("the same Title falls back to Date Imported, and the same time to the identifier")
func ties() {
    let early = book("Vol 1", imported: 10), late = book("Vol 1", imported: 20)
    #expect([late, early].ordered(by: .init(sort: .title, direction: .ascending)).map(\.id) == [early.id, late.id])
    let low = book("X", imported: 5, id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    let high = book("X", imported: 5, id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
    for sort in LibraryOrder.Sort.allCases {
        #expect([high, low].ordered(by: .init(sort: sort, direction: .ascending)).map(\.id) == [low.id, high.id])
    }
}

@Test("Descending is Ascending reversed, for every Sort and any starting arrangement of the array",
      arguments: LibraryOrder.Sort.allCases)
func descendingIsAscendingReversed(sort: LibraryOrder.Sort) {
    // six Books: two share a Title, two share an imported time, one was opened
    let ascending = books.ordered(by: .init(sort: sort, direction: .ascending))
    #expect(books.ordered(by: .init(sort: sort, direction: .descending)) == ascending.reversed())
    #expect(books.reversed().ordered(by: .init(sort: sort, direction: .ascending)) == ascending)
}

@Test("Imports stay first under every Library Order: In Progress, Queued, Failed, then Books",
      arguments: LibraryOrder.Sort.allCases, LibraryOrder.Direction.allCases)
func importsFirst(sort: LibraryOrder.Sort, direction: LibraryOrder.Direction)
// one Import per status (Queued twice, with different createdAt) and two Books; assert the item
// ids are [inProgress, queued earlier, queued later, failed] + the Books by ordered(by:)

@Test("the in-memory Library Order repository has none until one is saved")
@Test("the failing Library Order repository throws for the calls it is told to fail")
```

- [ ] **Step 2: Run them and see them fail to compile**

Run: `swift test --package-path app/FolioCore -Xswiftc -warnings-as-errors --filter "Library Order"`
Expected: build error, `LibraryOrder` not found.

- [ ] **Step 3: Implement `LibraryOrder` and `[Book].ordered(by:)`** in `Domain/LibraryOrder.swift`. Define one ascending comparison per Sort as the spec's table says (Recent: `lastOpenedAt ?? importedAt`, then `importedAt`, then `id.rawValue.uuidString`; Title: `localizedStandardCompare`, then `importedAt`, then the UUID string; Date Imported: `importedAt`, then the UUID string); Descending is `ascending.reversed()`.

- [ ] **Step 4: Change `[LibraryItem].inLibraryOrder()` to `inLibraryOrder(_ order: LibraryOrder)`**, ordering its Books with `ordered(by:)`. Update its one caller, `Library.items()`, to pass `LibraryOrder.initial` (Task 3 passes the real one), and the existing items-order test in `LibraryTests.swift` if it calls the function directly.

- [ ] **Step 5: Add the port, `InMemoryLibraryOrderRepository`, `FailingLibraryOrderRepository` and the two `RepositoryCall` cases**, in the files the Book and Import ones live in and in their shape.

- [ ] **Step 6: Run the whole package**

Run: `swift test --package-path app/FolioCore -Xswiftc -warnings-as-errors`
Expected: PASS, including every test that existed before.

- [ ] **Step 7: Build the app targets, format, commit**

Run: `./scripts/build.sh && ./scripts/format.sh --check`
Commit: `feat(library): the Library Order value, its ordering rule for Books and its repository port`

---

### Task 2: The Library Order in the Library's store (schema V3)

**Files:** Create `app/Folio/Persistence/LibraryOrderModel.swift`, `SwiftDataLibraryOrderRepository.swift`; Modify `FolioSchema.swift`, `LibraryStorage.swift`; Test `app/FolioTests/SwiftDataRepositoriesTests.swift`.

**Interfaces:**
- Consumes: `LibraryOrder`, `LibraryOrderRepository` (Task 1).
- Produces:
```swift
@Model final class LibraryOrderModel {
    var sort: String        // LibraryOrder.Sort's raw value
    var direction: String   // LibraryOrder.Direction's raw value
    init(_ order: LibraryOrder)
    func apply(_ order: LibraryOrder)
    /// `LibraryOrder.initial` when either raw value names no case.
    var libraryOrder: LibraryOrder { get }
}
@ModelActor actor SwiftDataLibraryOrderRepository: LibraryOrderRepository
enum FolioSchemaV3: VersionedSchema   // 3.0.0; [BookModel, ImportModel, LibraryOrderModel]
```

- [ ] **Step 1: Read Apple's documentation** for `VersionedSchema`, `SchemaMigrationPlan` and `MigrationStage.lightweight(fromVersion:toVersion:)`, and Core Data's "Using Lightweight Migration" on adding an entity. Note the sentences relied on for the implementation log.

- [ ] **Step 2: Write the failing tests** in `SwiftDataRepositoriesTests.swift`:

```swift
@Test("nothing saved reads as no Library Order")
// in-memory container; #expect(try await repository.libraryOrder() == nil)

@Test("the Library Order roundtrips, and a second save replaces the first")
// save (.title, .ascending) then (.dateImported, .descending); read gives the second;
// a fetch of LibraryOrderModel through a ModelContext on the same container counts 1 row

@Test("a stored Library Order that names no case reads as Recent, Descending")
// LibraryOrderModel(.initial) with sort = "pageCount"; #expect(model.libraryOrder == .initial)
// and again with direction = "sideways"

@Test("a store written by the second schema opens in the current one, with its Book and no Library Order")
func v2StoreOpensWithNoLibraryOrder() async throws
// as v1StoreOpensAsPageByPage: write Library.store with Schema(versionedSchema: FolioSchemaV2.self)
// holding one BookModel (readingMode "vertical", readingPosition 1); close it; open with
// LibraryStorage.makeContainer(at:); the Book reads back with the same id, Title, Pages, Reading
// Position and Reading Mode; SwiftDataLibraryOrderRepository on that container reads nil.
```

- [ ] **Step 3: Run them and see them fail to compile**

Run: `./scripts/test.sh macos`
Expected: build error, `SwiftDataLibraryOrderRepository` not found.

- [ ] **Step 4: Implement** `LibraryOrderModel`, the repository (read: the first row, nil when there is none; save: `apply` to the first row or insert one, then `modelContext.save()`), `FolioSchemaV3`, the `.lightweight(fromVersion: FolioSchemaV2.self, toVersion: FolioSchemaV3.self)` stage, and `LibraryStorage` opening V3 in both `makeContainer` paths. Update `FolioSchemaV1`'s header comment so it names V3 as done and V4 as the next. `FolioSchemaV2` keeps naming the live `BookModel` and `ImportModel`. If SwiftData refuses the same classes in two versions, freeze V2 copies the way V1's are frozen and record why in the log.

- [ ] **Step 5: Run the app's tests on both platforms**

Run: `./scripts/test.sh`
Expected: PASS, including `v1StoreOpensAsPageByPage`.

- [ ] **Step 6: Format, commit**

Commit: `feat(persistence): schema V3 stores the Library Order as one record`

---

### Task 3: The Library owns the Library Order; the model follows it

**Files:** Modify `Library/Library.swift`, `Library/LibraryError.swift`, `Domain/LibraryEvent.swift`, `Domain/Book.swift`, `Domain/Repositories.swift` (doc comment), `Domain/InMemoryRepositories.swift`, `app/Folio/Persistence/SwiftDataBookRepository.swift`, `app/Folio/Library/LibraryModel.swift`, `app/Folio/FolioApp.swift`; Test `LibraryTests.swift`, `LibraryErrorTests.swift`, `InMemoryRepositoriesTests.swift`, `app/FolioTests/SwiftDataRepositoriesTests.swift`, `LibraryModelTests.swift`, `NoticeTests.swift`.

**Interfaces:**
- Consumes: Task 1's value, rule, port and doubles; Task 2's `SwiftDataLibraryOrderRepository`.
- Produces:
```swift
// LibraryOperation
case chooseLibraryOrder = "Choose Library Order"
// LibraryEvent
case libraryOrderChanged(LibraryOrder)
// Library
public init(books: any BookRepository, imports: any ImportRepository,
            libraryOrders: any LibraryOrderRepository,
            pipeline: ImportPipeline, sourceAccess: any SourceAccess,
            now: @escaping @Sendable () -> Date = { .now })
public func libraryOrder() async throws(LibraryError) -> LibraryOrder          // .storage(.updateLibrary) on a read failure
public func chooseLibraryOrder(_ order: LibraryOrder) async throws(LibraryError) // .storage(.chooseLibraryOrder) on a save failure
// LibraryModel
private(set) var libraryOrder: LibraryOrder   // starts .initial
func chooseLibraryOrder(_ order: LibraryOrder) async
```

- [ ] **Step 1: Write the failing Library tests** in `LibraryTests.swift`. Give the test `Fixture` a `libraryOrders:` parameter defaulting to `InMemoryLibraryOrderRepository()` and pass it to `Library.init`.

```swift
@Test("with nothing saved the Library Order is Recent, Descending")
// #expect(try await fixture.library.libraryOrder() == .initial)

@Test("chooseLibraryOrder saves the Library Order and emits libraryOrderChanged")
// choose (.title, .ascending); events == [.libraryOrderChanged(order)]; repository reads order;
// library.libraryOrder() == order

@Test("chooseLibraryOrder with the Library Order in force announces nothing and saves nothing")
// FailingLibraryOrderRepository failing [.saveLibraryOrder]; choose .initial with nothing saved:
// no throw, no events. Then with (.title, .ascending) already saved in its base, choose it again: same.

@Test("chooseLibraryOrder that cannot save throws storage(.chooseLibraryOrder) and announces nothing")
// failing [.saveLibraryOrder]; #expect(throws: LibraryError.storage(.chooseLibraryOrder));
// events empty; library.libraryOrder() == .initial

@Test("items follow the chosen Library Order")
// three Books titled "B", "A", "C" with imported times 1, 2, 3; choose (.title, .ascending);
// the Book Titles in items() are ["A", "B", "C"]; choose (.dateImported, .descending): ["C", "A", "B"]

@Test("items with a Library Order that cannot be read throws storage(.updateLibrary)")
// failing [.libraryOrder]

@Test("opening a Book moves it under Recent and not under Title")
// two Books; open the older; under .initial it is first in items(); under (.title, .ascending)
// the Titles stay alphabetical
```
In `LibraryErrorTests.swift` add Choose Library Order to the storage-failure table (the operation, the Library Order repository, the `saveLibraryOrder` call) and to the switch that runs each operation, in the table's own shape.

- [ ] **Step 2: Run them and see them fail to compile**

Run: `swift test --package-path app/FolioCore -Xswiftc -warnings-as-errors --filter Library`
Expected: build error, no `libraryOrders:` parameter.

- [ ] **Step 3: Implement in `Library`**: the stored repository, `libraryOrder()` (saved one or `.initial`, inside `storageGuard(.updateLibrary)`), `chooseLibraryOrder` (inside `storageGuard(.chooseLibraryOrder)`: read; return if equal; save; yield the event), and `items()` reading the Library Order inside its existing guard and passing it to `inLibraryOrder(_:)`. Add the operation and the event.

- [ ] **Step 4: Stop the repositories ordering Books.** `BookRepository.allBooks()`'s doc comment becomes "Every Book, in no promised order." `InMemoryBookRepository.allBooks()` and `SwiftDataBookRepository.allBooks()` return the Books without `inLibraryOrder()`; then delete `[Book].inLibraryOrder()` from `Book.swift`. Rewrite the two repository tests that asserted Library order ("allBooks returns Library order…" in `InMemoryRepositoriesTests.swift`, "allBooks uses Library order" in `SwiftDataRepositoriesTests.swift`) to assert the set of Books returned.

- [ ] **Step 5: Run the package**

Run: `swift test --package-path app/FolioCore -Xswiftc -warnings-as-errors`
Expected: PASS.

- [ ] **Step 6: Write the failing model tests** in `LibraryModelTests.swift`. Give `makeFixture` a `libraryOrders:` parameter defaulting to `InMemoryLibraryOrderRepository()`; pass an in-memory one in `NoticeTests.swift`'s `Library(` call too.

```swift
@Test("choosing a Library Order reorders the items and updates libraryOrder")
// Books "B", "A"; start the model as the rename test does; choose (.title, .ascending);
// wait for the event the way that test does; model.libraryOrder == order;
// the Book Titles in model.items are ["A", "B"]; model.notices.isEmpty

@Test("the model starts with the Library Order that was saved")
// save (.dateImported, .ascending) in the repository before start; after start
// model.libraryOrder is that one and items follow it
```
Add Choose Library Order to the write-failure table that asserts each operation's Notice (title "Couldn't Choose Library Order", the "couldn't save the change. Try again…" message), with its row in the `switch` calling `await model.chooseLibraryOrder(LibraryOrder(sort: .title, direction: .ascending))` and the failing repository failing `saveLibraryOrder`. Extend that test, or add one beside it, to assert that after the failure `model.libraryOrder == .initial` and `model.items` is unchanged.

- [ ] **Step 7: Implement in `LibraryModel`**: `libraryOrder`, loaded in `loadItems()` beside the items (one failure, one Update the Library Notice, as now); `chooseLibraryOrder` through `perform(.chooseLibraryOrder)`; `handle` takes `.libraryOrderChanged(let order)`: set `libraryOrder`, then `reload()`. Fix the two comments that say "Library order" (`open`) to say the Recent Sort. `FolioApp.makeModel` passes `SwiftDataLibraryOrderRepository(modelContainer: container)`.

- [ ] **Step 8: Run everything**

Run: `./scripts/test.sh && ./scripts/format.sh --check`
Expected: PASS on every platform.

- [ ] **Step 9: Commit**

Commit: `feat(library): the Library owns its Library Order, orders its items by it and announces LibraryOrderChanged`

---

### Task 4: The Sort menu

**Files:** Create `app/Folio/Library/LibraryOrderMenu.swift`, `app/FolioTests/LibraryOrderMenuTests.swift`; Modify `LibraryView.swift`, `LibraryWindow.swift`, `LibraryCommands.swift`, `Localizable.xcstrings`.

**Interfaces:**
- Consumes: `LibraryModel.libraryOrder`, `LibraryModel.chooseLibraryOrder(_:)` (Task 3).
- Produces:
```swift
extension LibraryOrder.Sort { var label: LocalizedStringResource { get } }        // "Recent", "Title", "Date Imported"
extension LibraryOrder.Direction { var label: LocalizedStringResource { get } }   // "Ascending", "Descending"
/// The two groups, Sorts then Directions, with no headings; the current ones ticked.
struct LibraryOrderPickers: View {
    let order: LibraryOrder
    let choose: (LibraryOrder) -> Void
}
/// What the Mac's View menu needs from the focused window.
struct LibraryOrderChoice { let order: LibraryOrder; let choose: (LibraryOrder) -> Void }
extension FocusedValues { var libraryOrderChoice: LibraryOrderChoice? { get set } }   // macOS only
```

- [ ] **Step 1: Read the HIG** pages "Menus", "Toolbars" and "The menu bar" (View menu), and SwiftUI's `Picker` in a `Menu`, `pickerStyle(.inline)`, `labelsHidden`, `CommandGroup(before:)`/`CommandGroupPlacement.toolbar` and `focusedSceneValue`. Note what is relied on for the log. Choose the toolbar symbol and placement from them (spec: left to the builder).

- [ ] **Step 2: Write the failing test** in `LibraryOrderMenuTests.swift`:

```swift
@Test("every Sort and every Direction has its own label")
// String(localized: label) for all cases: ["Recent", "Title", "Date Imported"] and ["Ascending", "Descending"]

@Test("picking a Sort keeps the Direction, and picking a Direction keeps the Sort")
// LibraryOrderPickers' two bindings are built by static functions so they can be tested:
// LibraryOrderPickers.sortBinding(order:choose:) and .directionBinding(order:choose:);
// setting the Sort binding of (.recent, .ascending) to .title calls choose with (.title, .ascending);
// setting the Direction binding to .descending calls choose with (.recent, .descending)
```

- [ ] **Step 3: Run it and see it fail to compile**

Run: `./scripts/test.sh macos`

- [ ] **Step 4: Implement `LibraryOrderMenu.swift`**: the labels; `LibraryOrderPickers` as two inline `Picker`s with hidden labels over `Sort.allCases` and `Direction.allCases`, separated by a `Divider`, their bindings reading `order` and calling `choose` with the other half unchanged.

- [ ] **Step 5: Add the toolbar menu in `LibraryView`**: a `Menu("Sort", systemImage: …)` holding `LibraryOrderPickers(order: model.libraryOrder) { order in Task { await model.chooseLibraryOrder(order) } }`, with `.help("Sort")` on Mac. It is disabled when the Library has no Books (`hasBooks`). It must not displace Import or the iPad's Select button.

- [ ] **Step 6: Add the Mac View-menu submenu**: `LibraryWindow` publishes `.focusedSceneValue(\.libraryOrderChoice, LibraryOrderChoice(order: model.libraryOrder, choose: …))`; `LibraryCommands` adds `CommandGroup(before: .toolbar) { Menu("Sort By") { … } }` holding `LibraryOrderPickers` when a choice is focused, and a disabled "Sort By" when none is.

- [ ] **Step 7: Sync the string catalog** as `CLAUDE.md` describes, with the stringsdata of both platforms; restore compact `{}` entries. Expected new keys: "Sort", "Sort By", "Recent", "Title", "Date Imported", "Ascending", "Descending", and "Couldn't Choose Library Order" if the catalog lists the Notice titles.

- [ ] **Step 8: Run the tests, then check on a simulator**

Run: `./scripts/test.sh`
Then with `SIMULATOR=<udid of a single-display iPhone> ./scripts/run.sh ios`, using the `sim-use` skill: import or reuse at least three Books with different Titles; choose Title, then Ascending and Descending; choose Date Imported; choose Recent; open a Book under Recent and under Title and return; terminate and relaunch and confirm the choice and the ticks are kept; rename a Book under Title. Repeat the menu and relaunch checks on an iPad simulator, with the Select button visible. Record what was seen, with the device and iOS version.

- [ ] **Step 9: Format, commit**

Commit: `feat(library): a Sort menu chooses the Library Order on iPhone, iPad and Mac`

---

### Task 5: Decisions, the log and the owner's check list

**Files:** Modify `DECISIONS.md`, `CLAUDE.md`; Create `docs/logs/2026-11-11-NN-library-order-implementation.md`.

- [ ] **Step 1: `DECISIONS.md`**: add the five entries the spec lists under "Decision log entries this slice must add", in plain language, each stating what the user experiences. Correct the earlier entry that says there is one Library order if one exists.

- [ ] **Step 2: `CLAUDE.md`**: in "Library and Import code", add `LibraryOrder` and its ordering rule to `Domain/`, the `LibraryOrderRepository` port, `LibraryOrderModel` and `SwiftDataLibraryOrderRepository` to `Persistence/`, and the Sort menu to `Library/`.

- [ ] **Step 3: The implementation log**, in the structure the Reading Mode log uses: summary, what changed per task, Apple documentation relied on (quoted), what the documentation does not say (observed), simulator checks, tests, what was discovered, not checked, commits. Write every ruling in plain language for the owner.

- [ ] **Step 4: The owner's check list** in that log, covering at least the items the spec names: each Sort in both Directions on iPhone, iPad and Mac; relaunch keeps the choice; two Mac windows follow each other; the View menu's "Sort By" submenu, also with no Library window focused; a Library from the previous version opens in Recent, Descending with every Book in place; rename under Title; opening a Book under Recent and under Title. Mark each as seen on a simulator or not checked.

- [ ] **Step 5: The gate**

Run: `./scripts/verify.sh`
Expected: "green — all enabled platforms format, build, test, and launch".

- [ ] **Step 6: Commit**

Commit: `docs(library): record the Library Order decisions and the owner's check list`
