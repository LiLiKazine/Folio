# Library Order — Design

Date: 2026-11-11
Status: ready for approval
Glossary: `CONTEXT.md` is authoritative. Capitalised terms are glossary terms.
Builds on: `2026-11-08-library-and-import-design.md` (the Library, its
events, its repositories) and `2026-11-08-visible-failures-design.md` (a
failed action shows a Notice).

## Intent

Today the Library shows Books in one order: the Book last opened, or imported
if never opened, comes first. A reader looking for a Book by its Title, or for
the Books they imported lately, has to scan the grid. This slice lets the
reader choose what Books are ordered by and which way, and the Library
remembers the choice.

## What the owner decided (this conversation)

- **Two separate choices**: what to order by, and which way. Not one list of
  combined rules.
- **Three Sorts**: Recent (today's order), Title, Date Imported.
- **Two Directions**: Ascending and Descending, applied to whichever Sort is
  chosen.
- **The glossary gains Library Order, Sort and Direction, and the event
  LibraryOrderChanged.** Already applied to `CONTEXT.md`. BookOpened is now
  "the basis for the Recent Sort". "Date Imported" replaces the owner's
  "added time", because the glossary avoids "add" for an Import; "Title"
  replaces "name".
- **The Library owns the Library Order.** It is part of the Library, as a
  Reading Mode is part of a Book: the Library saves it and announces
  LibraryOrderChanged. It is not a preference of a screen.
- **It is saved in the Library's database**, not in the device's settings
  store. The owner chose this over the designer's recommendation.
- **Date Imported is the time a Book already stores**: the moment its Import
  began copying Pages. Not when the Import finished, not when the Source was
  picked, not the Source's own date on disk.
- **The starting Library Order is Recent, Descending**, so a reader who never
  opens the menu sees no change.
- **Switching the Sort keeps the Direction.** Nothing flips by itself.
- **One Library Order for the whole Library and every window**, remembered
  across launches.
- **Imports that have not produced a Book stay at the front**, in the order
  they have today, whatever the Library Order.
- **A failed save leaves the grid in its old order and shows a Notice.**
  (Reading Mode differs: it switches on screen and only logs. The owner
  agreed the stricter rule here.)
- **Choosing the Library Order the Library already has changes nothing and
  announces nothing.**

## Calls made by the designer

The owner agreed "all of your calls"; they are listed so they can be checked.

- **Title comparison** ignores case and counts numbers as numbers, by the
  device's language rules: "vol 2", "Vol 3", "Vol 10" in that order.
- **Ties** (two Books with the same Title, or the same time) are broken by
  Date Imported, and after that by the Book's identifier, so the order is
  total and the grid never shuffles between reloads.
- **Descending is the exact reverse of Ascending** for Books, ties included.
  Flipping the Direction twice gives back the same grid.
- **The menu has no "Order" heading.** In this conversation the designer said
  the menu could be headed "Sort By" and "Order". `CLAUDE.md` requires UI
  copy to use glossary terms exactly, and the glossary now avoids "order" on
  its own for a Direction. So the menu is two groups separated by a divider,
  the three Sorts and then the two Directions, with no heading on either
  group. On the Mac's View menu both groups sit in a "Sort By" submenu.
- **The control** is a toolbar menu on iPhone, iPad and Mac, labelled "Sort",
  plus the View menu submenu on Mac.
- **Operation name**: Choose Library Order, which is also what the Notice
  for a failed save names.
- **A stored Library Order this version does not recognise**, written by a
  later version, reads as Recent, Descending, so the Library still opens.
  The same rule Reading Mode follows.

## Goals

- The reader can choose a Sort and a Direction from the Library screen on
  iPhone, iPad and Mac.
- The grid reorders as soon as the choice is saved, in every window.
- The choice survives relaunch.
- A Library made by the previous version opens unchanged, in Recent,
  Descending.
- The ordering rule is pure and tested without a screen or storage.

## Non-goals

- Grouping Books into sections, filtering, or searching.
- More Sorts (Page count, Reading Position, the Source's date).
- A Library Order per window, or per device kept in sync.
- Changing the order of Imports that have not produced a Book.
- Changing how Pages are ordered inside a Book.

## Anti-goals

- A grid that reorders while the reader is tapping a Book. Opening a Book
  still does not reload the grid (`LibraryModel.open`); under Recent the Book
  moves to the front the next time the Library screen appears, as today.
- A choice that looks saved and is gone at next launch.
- An upgrade that loses or reorders anything in an existing Library.

## Domain model

### Values (FolioCore, `Domain/`)

- `LibraryOrder`: a `Sort` and a `Direction`. `Equatable`, `Sendable`,
  `Codable`. Two Library Orders with the same Sort and Direction are equal;
  it has no identity. `LibraryOrder.initial` is Recent, Descending.
- `LibraryOrder.Sort`: `recent`, `title`, `dateImported`. String raw values,
  `CaseIterable`.
- `LibraryOrder.Direction`: `ascending`, `descending`. String raw values,
  `CaseIterable`.

### The ordering rule (FolioCore, pure)

Books in a Library Order. It replaces `[Book].inLibraryOrder()`.

Ascending is defined first, as a total order:

| Sort | Compared by, in order |
|---|---|
| Recent | `lastOpenedAt ?? importedAt` earlier first; then `importedAt` earlier first; then the identifier's UUID string |
| Title | Title by `localizedStandardCompare` (Apple: for strings "presented in lists and tables where Finder-like sorting is appropriate"), ascending; then `importedAt` earlier first; then the identifier's UUID string |
| Date Imported | `importedAt` earlier first; then the identifier's UUID string |

Descending is that list reversed.

`[LibraryItem].inLibraryOrder()` takes the Library Order: Imports In
Progress, then Queued by `createdAt`, then Failed by `createdAt`, exactly as
today, then Books by the rule above.

Recent, Descending must put Books with different times in the order today's
rule does. Books with equal times may land differently from today (today
ties go by identifier ascending); nothing visible depends on that.

### Invariants

- The Library always has a Library Order. One that was never saved is
  `LibraryOrder.initial`.
- Only the Library changes the Library Order.
- LibraryOrderChanged is announced only after the save succeeded.

### Port (FolioCore, `Domain/Repositories.swift`)

```swift
public protocol LibraryOrderRepository: Sendable {
    /// The saved Library Order; nil when none was ever saved.
    func libraryOrder() async throws -> LibraryOrder?
    func save(_ order: LibraryOrder) async throws
}
```

With an in-memory implementation and a failing test double beside the
existing ones for Books and Imports.

`BookRepository.allBooks()` stops promising Library order: it returns every
Book, and the Library orders them. Its implementations stop sorting by
Library order.

### Operations on the `Library` actor

- `libraryOrder() async throws(LibraryError) -> LibraryOrder`: the saved
  one, or `initial`. A read failure throws `.storage(.updateLibrary)`.
- `chooseLibraryOrder(_ order: LibraryOrder) async throws(LibraryError)`:
  the same Library Order returns without saving or announcing; otherwise
  saves, then yields `.libraryOrderChanged(order)`. A save failure throws
  `.storage(.chooseLibraryOrder)`.
- `items()` reads the Library Order and returns the items in it. If the
  Library Order cannot be read, it throws `.storage(.updateLibrary)` like
  any other read failure there.
- `Library.init` gains the `LibraryOrderRepository`.
- `LibraryOperation` gains `chooseLibraryOrder = "Choose Library Order"`.

### Event

`LibraryEvent.libraryOrderChanged(LibraryOrder)`.

## Behaviour

Each line is a case the owner agreed.

- **Recent, and the reader opens a Book from the middle of the grid.** When
  they come back it is first (Descending) or last (Ascending).
- **Title, and the reader opens that Book.** It does not move.
- **Title, and the reader renames "Zeta" to "Alpha".** It moves to its new
  place when the rename is saved (BookRenamed already reloads the grid).
- **Date Imported.** Nothing a reader does moves a Book; a completed Import
  adds one at the newest end.
- **A new Book arrives under Title.** It appears at its place by Title, not
  at the front.
- **Imports In Progress, Queued or Failed** stay at the front under every
  Library Order and both Directions.
- **Two Mac windows show the Library and the reader picks Title in one.**
  Both show Title order. There is one `LibraryModel` for the app, so this
  follows from the model reloading on LibraryOrderChanged.
- **The save fails.** The grid keeps its order, the menu still shows the old
  choice ticked, and a Notice names Choose Library Order.
- **The reader picks what is already ticked.** Nothing happens.
- **A selection** (Mac, or the iPad's select mode) is kept across a reorder;
  it is held by Book identifier.

## Architecture

### FolioCore

- `Domain/LibraryOrder.swift`: the three values and the ordering rule for
  Books.
- `Domain/Repositories.swift`, `InMemoryRepositories.swift`,
  `FailingRepositories.swift`: the port and its two test implementations.
  `RepositoryCall` gains what the failing double needs.
- `Domain/LibraryEvent.swift`, `Library/LibraryError.swift`: the event and
  the operation.
- `Library/Library.swift`: the two operations, `items()`, `init`.
- `Library/LibraryItem.swift`: `inLibraryOrder` takes the Library Order.
- `Domain/Book.swift`: `[Book].inLibraryOrder()` is removed.

### App: persistence

- `LibraryOrderModel`: a SwiftData model with the Sort's and the
  Direction's raw values as text. At most one row. Raw values that name no
  case read as `LibraryOrder.initial`.
- `SwiftDataLibraryOrderRepository`: reads the first row; saves by updating
  it or inserting it.
- `FolioSchemaV3`: V2's two models plus `LibraryOrderModel`.
  `FolioMigrationPlan` gains a lightweight stage from V2 to V3, and
  `LibraryStorage` opens V3. `BookModel` and `ImportModel` do not change,
  so V2 keeps naming the live classes. The builder confirms from Apple's
  documentation that adding a model is a lightweight change, and proves it
  with a test that writes a V2 store holding a Book and opens it with V3.
  If SwiftData does not accept the same classes in two versions, the
  builder freezes V2 copies as V1's are frozen, and records why.
- `SwiftDataBookRepository.allBooks()` no longer sorts by Library order.

### App: Library

- `LibraryModel` holds `private(set) var libraryOrder: LibraryOrder`,
  loaded with the items, and
  `func chooseLibraryOrder(_ order: LibraryOrder) async`, which goes through
  `perform(.chooseLibraryOrder)` so a failure queues its Notice. On
  `.libraryOrderChanged` it takes the new Library Order and reloads.
- `LibraryView`: a toolbar `Menu` labelled "Sort" (the builder picks the
  symbol and the placement per platform from the HIG) holding two inline
  `Picker`s, the Sorts then the Directions, the current ones ticked. Each
  pick calls `chooseLibraryOrder` with the other half unchanged. The ticks
  follow `model.libraryOrder`, so they move only once the save succeeded.
- `LibraryCommands` (Mac): a "Sort By" submenu in the View menu with the
  same two groups, reaching the focused window the way Import… does, and
  disabled when no Library window is focused.
- `FolioApp.makeModel` passes the new repository.
- `Notice`: the title for Choose Library Order follows the pattern the
  other operations use.

### Strings

New in `Localizable.xcstrings`: "Sort", "Sort By", "Recent", "Title" (as a
Sort), "Date Imported", "Ascending", "Descending", and the Notice title for
Choose Library Order. Sync the catalog as `CLAUDE.md` describes.

## Tests

- The ordering rule, per Sort and Direction: different keys; the Title
  cases ("vol 2", "Vol 3", "Vol 10"; case ignored); ties by Date Imported
  then identifier; Descending equals Ascending reversed; a Book never
  opened sorts by its imported time under Recent.
- `[LibraryItem]`: Imports first under every Library Order.
- `Library`: no saved Library Order gives `initial`; choosing saves and
  announces; choosing the same one does neither; a forced save failure
  throws `.storage(.chooseLibraryOrder)` and announces nothing; `items()`
  follows the chosen Library Order; a forced read failure in `items()`
  throws `.storage(.updateLibrary)`.
- Persistence: the Library Order roundtrips; nothing saved reads nil; raw
  values that name no case read as `initial`; a V2 store opens in V3 with
  its Book unchanged and no Library Order.
- `LibraryModel`: choosing reorders `items` and updates `libraryOrder`; a
  forced failure queues the Choose Library Order Notice and leaves both
  unchanged (the project's rule: every operation has a test that forces its
  failure and asserts the Notice).

## Constraints

- Swift 6 strict concurrency; SwiftUI only; no third-party dependencies.
- `./scripts/verify.sh` green on every platform; warnings are errors.
- Glossary terms exactly, in code, copy, tests and commits; none of the
  _Avoid_ words.
- Designs rest on Apple's documentation; where it is silent, the builder
  says what was observed instead.

## Decision log entries this slice must add

In `DECISIONS.md`, in plain language:

- The Library Order is a Sort and a Direction, chosen separately, and why.
- The Library owns it and saves it in its own database; the settings store
  was considered and the owner chose the database. Consequence: the third
  database version, and what a version 2 Library experiences (nothing
  visible).
- What each Sort compares, including Date Imported being the moment the
  Import began copying, and the three alternatives rejected.
- A failed save leaves the grid as it was and shows a Notice, unlike
  Reading Mode.
- The menu has no "Order" heading, and why.

`CLAUDE.md`'s "Library and Import code" section is updated for the new
value, port, model and repository.

## The owner's check list

The builder writes one in the decision log, covering at least: each Sort in
both Directions on iPhone, iPad and Mac; relaunch keeps the choice; two Mac
windows follow each other; the View menu submenu; a Library from the
previous version opens in Recent, Descending with every Book in place;
rename under Title; opening a Book under Recent and under Title.

## Left to the builder

- The toolbar symbol and placement on each platform, from the HIG.
- Whether the grid animates when it reorders. Default: whatever SwiftUI
  does with no animation added.
- Where the scroll position rests after a reorder. Default: wherever the
  scroll view leaves it; nothing is scrolled by code.
- Whether the Library reads the Library Order from the repository each
  time or keeps it after the first read.
- The exact shape of the Mac command's focused value.
