# 2026-11-11-02: Library Order — implementation

**Status:** In progress. Task 1 of 5 is done (the Library Order value, its
ordering rule for Books, and the place it will be saved, in FolioCore). Nothing
a user can see has changed yet. The owner's check list and the final summary are
written by Task 5.

## Context

The design rulings are in `docs/logs/2026-11-11-01-library-order-design.md`; the
design is `docs/superpowers/specs/2026-11-11-library-order-design.md` and the
plan is `docs/superpowers/plans/2026-11-11-library-order.md`. This one log
collects what each task changed, what Apple's documentation says about what it
relies on, what was observed instead, and what could not be checked. Terms: a
*port* is the short list of operations the Library needs from storage, written
in FolioCore so the Library does not depend on how the app stores things; a
*stand-in* is storage that keeps things in memory only and is used by tests in
place of the real storage; a *failing stand-in* is one that can be told to fail
chosen operations, to test what the user sees when storage fails. A *tie* is
two Books that the chosen Sort cannot tell apart.

## Task 1: The Library Order value, its ordering rule and its port (FolioCore)

### What Changed

- `Domain/LibraryOrder.swift` (new): `LibraryOrder`, a Sort (`recent`, `title`,
  `dateImported`) and a Direction (`ascending`, `descending`), with
  `LibraryOrder.initial` as Recent, Descending. `[Book].ordered(by:)` puts Books
  in a Library Order. Each Sort defines one Ascending comparison and Descending
  is that list reversed, so flipping the Direction twice gives the same list
  back, ties included:
  - Recent: the time last opened, or the time imported if never opened, earlier
    first; then the time imported; then the Book's identifier written as text.
  - Title: compared the way Finder compares file names, ignoring case and
    reading digits as numbers; then the time imported; then the identifier.
  - Date Imported: the time imported, then the identifier.
- `Library/LibraryItem.swift`: `[LibraryItem].inLibraryOrder(_:)` now takes a
  Library Order and orders its Books with `ordered(by:)`. Imports that have not
  produced a Book still come first (In Progress, then Queued by creation time,
  then Failed by creation time), whatever the Library Order.
- `Library/Library.swift`: the one caller, `items()`, passes
  `LibraryOrder.initial` for now; Task 3 makes the Library own the real one.
- `Domain/Repositories.swift`, `InMemoryRepositories.swift`,
  `FailingRepositories.swift`: the port `LibraryOrderRepository` (read the
  saved Library Order, which is nothing when none was ever saved; save one), its
  stand-in `InMemoryLibraryOrderRepository`, its failing stand-in
  `FailingLibraryOrderRepository`, and two new `RepositoryCall` cases
  (`libraryOrder`, `saveLibraryOrder`) so a test can name which of the two to
  fail.
- Left as the plan says: `[Book].inLibraryOrder()` (used by the in-memory Book
  stand-in and the app's stored-Book repository) stays until Task 3 removes it.
  What a user sees is unchanged: Recent, Descending, as today.

### Tests

New suite `Library Order` (`LibraryOrderTests.swift`), nine tests:

- the starting Library Order is Recent, Descending;
- Recent uses the last open, or the Import time when never opened, in both
  Directions;
- Title puts "vol 2", "Vol 3", "Vol 10" in that order and the reverse for
  Descending;
- Date Imported ignores opens;
- a tie on Title falls back to the Import time, and a tie on time to the
  identifier, for every Sort;
- for every Sort, Descending equals Ascending reversed, and the result does not
  depend on the order the Books were handed in (six Books: two share a Title, two
  share an Import time, one was opened);
- for every Sort and Direction, Imports stay first: In Progress, the two Queued
  by creation time, Failed, then the Books in their Library Order;
- the stand-in has no Library Order until one is saved, and keeps the latest one
  saved;
- the failing stand-in throws `RepositoryFailure` for exactly the calls it is
  told to fail, leaves the saved value untouched when a save fails, and works
  again after `succeed()`.

No existing test called `[LibraryItem].inLibraryOrder()` directly; the
items-order tests in `LibraryTests` go through `Library.items()`, which still
yields today's order, and passed unchanged.

### Apple documentation relied on

Fetched on 2026-11-11 from
`developer.apple.com/tutorials/data/documentation/foundation/nsstring/localizedstandardcompare(_:).json`:

- `localizedStandardCompare(_:)`: "Compares strings as sorted by the Finder."
  and "This method should be used whenever file names or other strings are
  presented in lists and tables where Finder-like sorting is appropriate. The
  exact sorting behavior of this method is different under different locales and
  may be changed in future releases. This method uses the current locale."

### What the documentation does not say (observed)

- Apple's page does not say that case is ignored or that digits count as
  numbers; it says only "Finder-like". That "vol 2" comes before "Vol 3" before
  "Vol 10" is observed: the test `title` passes on this Mac (macOS 27 SDK, the
  device's own language settings). Because the method "uses the current
  locale", the same Titles could come out differently under another language; the
  tests have only been run under this Mac's.

### Gate

- FolioCore: `swift test --package-path app/FolioCore -Xswiftc -warnings-as-errors`:
  100 tests in 9 suites passed (the nine new ones included). Before the code
  existed the test target failed to compile (`LibraryOrder`, `ordered(by:)` and the
  two repositories not found), as the plan expects.
- `./scripts/build.sh`: iOS and macOS Debug builds succeeded.
- `./scripts/format.sh --check`: clean.
- App tests not run for this task: no app code changed (the app target only had
  to keep compiling).

### Not checked

- Nothing a user sees has changed, so nothing was launched.
- Title order under any language other than this Mac's.
