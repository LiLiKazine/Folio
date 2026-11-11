# 2026-11-11-02: Library Order — implementation

**Status:** In progress. Tasks 1 to 3 of 5 are done (the Library Order value
and its ordering rule, where it is saved, and the Library keeping it and the
Library screen's model following it). Nothing a user can see has changed yet:
there is no menu to choose a Library Order. The owner's check list and the final summary are
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


## Task 2: The Library Order in the Library's store (schema V3)

Terms: the *store* is the file on the device where the Library keeps its Books
and Imports; a *schema* is the list of kinds of record the store holds, and each
numbered *schema version* is one such list; a *migration* is how a store written
in an older schema version is brought up to the current one when the app opens it;
a *lightweight* migration is one SwiftData works out by itself from the
difference between the two versions, with no code of ours.

### What Changed

- `Persistence/LibraryOrderModel.swift` (new): the stored form of the Library
  Order, two text fields holding the Sort's and the Direction's raw values. If
  either text names no Sort or no Direction (a store from some future or damaged
  state), it reads as Recent, Descending, the starting Library Order, so a bad
  value never stops the Library opening.
- `Persistence/SwiftDataLibraryOrderRepository.swift` (new): the stored
  version of the `LibraryOrderRepository` port. Reading gives the first stored
  row, or nothing when none was ever saved. Saving changes that row, or adds one
  if there is none, and then writes the store. There is never more than one row.
- `Persistence/FolioSchema.swift`: schema version 3.0.0 (`FolioSchemaV3`) is the
  Book and Import records plus the Library Order record. The migration plan lists
  it and gains a lightweight stage from version 2 to version 3. Version 2 still
  names the live `BookModel` and `ImportModel`, because neither changed. The
  comment on version 1 now names V3 as done and V4 as the next, and V2's comment
  no longer calls itself the current shape.
- `Persistence/LibraryStorage.swift`: both ways of opening the Library
  (in memory, and from the store file) open version 3.
- Not done, as the plan says: nothing uses the new repository yet. Task 3 wires
  it into the Library and the app, so what a user sees is unchanged.

### Tests

In `SwiftDataRepositoriesTests.swift`, four new tests:

- nothing saved reads as no Library Order;
- the Library Order roundtrips, and a second save replaces the first (one row
  remains, checked by fetching from a second context on the same container);
- a stored Library Order that names no case reads as Recent, Descending (once
  with a Sort that does not exist, once with a Direction that does not exist);
- `v2StoreOpensWithNoLibraryOrder`: a store written in schema version 2 holding
  one Book (Reading Mode Vertical, Reading Position 1) opens in version 3 with
  that Book's id, Title, Pages, Reading Position and Reading Mode unchanged, and
  reading the Library Order gives nothing.

The compile failure came first (`SwiftDataLibraryOrderRepository` and
`LibraryOrderModel` not found), as the plan expects.

The existing `v1StoreOpensAsPageByPage` still passes, now through both stages
(1 to 2, then 2 to 3).

Do the stages matter? The version 1 test's own comment says it would pass with
no stages; that was true when there was one stage and the store was already
close to current. I checked this for version 3 by taking the 2-to-3 stage out and
running the tests: both the version 1 test and the version 2 test failed (SwiftData
reported `unknownDataStoreSchema`, and Core Data error 134504 appeared in the log),
and both passed again with the stage back. So the new stage is what opens a
version 2 store, and a version 1 store needs it too, as its second step.
(Observed, not documented.)

### Apple documentation relied on

Fetched on 2026-11-11 from `developer.apple.com/tutorials/data/documentation/`
(the JSON behind each page):

- `swiftdata/versionedschema` (`VersionedSchema`): "An interface for describing a
  specific version of a schema, including the models it contains." Its `models`
  property: "The models to include in this version of the schema." Its
  `versionIdentifier`: "The textual description of the migration's version or
  purpose." That is why `FolioSchemaV3` lists all three models and has its own
  version number.
- `swiftdata/schemamigrationplan` (`SchemaMigrationPlan`): "An interface for
  describing the evolution of a schema and how to migrate between specific
  versions." The plan lists each schema version and the stages between them.
- `swiftdata/migrationstage` (`MigrationStage`): "Describes a migration between
  two versions of the same schema." Its case
  `lightweight(fromVersion:toVersion:)` takes two `VersionedSchema` types and has
  no further prose on the page.
- `coredata/migrating-your-data-model-automatically` ("Migrating Your Data Model
  Automatically"; SwiftData's stores are Core Data stores, but this is Core Data's
  page, not SwiftData's): "Core Data can typically perform an automatic data
  migration, referred to as lightweight migration. Lightweight migration infers
  the migration from the differences between the source and the destination
  managed object models." and "You can add, remove, and rename entities in the
  hierarchy." Adding a record kind, which is all version 3 does, is therefore a
  change a lightweight migration handles. The brief named a page called "Using
  Lightweight Migration"; that address returned nothing, and this page is the
  Core Data page on the same subject.

### What the documentation does not say (observed)

- The SwiftData pages above are one-sentence summaries. They do not say whether
  the same model classes may appear in two schema versions, which is what
  version 2 and version 3 do for `BookModel` and `ImportModel`. Observed: SwiftData
  accepts it. The container opens, the migration runs, and the version 1 and
  version 2 tests pass. So the fallback in the brief (freezing copies of the
  version 2 models, as version 1's are frozen) was not needed and was not used.
- The SwiftData pages also do not say that a lightweight stage from 2 to 3 is
  enough when the only difference is a new model. What the Core Data page says is
  quoted above; that it holds under SwiftData is observed from the two tests.

### Gate

- `./scripts/test.sh`: FolioCore 100 tests in 9 suites passed (warnings as
  errors); the app's tests passed on the iOS simulator and on macOS, 128 tests in
  13 suites on macOS, the four new ones included.
- `./scripts/format.sh --check`: clean.
- The app's test build prints existing warnings about calling main-actor
  methods from non-main-actor test code in `LibraryWindowTests.swift` and
  the reading tests; none is in code this task wrote.

### Not checked

- Opening a store written by a real earlier build of the app (only stores
  written by the tests, with version 1 and version 2 of the schema, were opened).
- Nothing a user sees has changed, so nothing was launched.

## Task 3: The Library owns the Library Order; the model follows it

### What Changed

- The Library now takes the place where the Library Order is saved as one more
  piece of storage, and answers two new questions. `libraryOrder()` gives the
  saved Library Order, or Recent, Descending when none was ever chosen.
  `chooseLibraryOrder(_:)` saves a chosen one and announces
  `LibraryOrderChanged` with it. Choosing the Library Order already in force
  saves nothing and announces nothing. A save that fails throws the Choose
  Library Order failure; a read that fails throws the Update the Library failure,
  the same one the grid already uses.
- The Library's list of items now reads the Library Order each time and puts
  the Books in it. Imports that have not produced a Book still come first, as
  before. Opening a Book still changes only the time the Recent Sort uses; under
  the Title Sort the Books stay in alphabetical order.
- Storage no longer orders Books. The Book storage (the in-memory stand-in and
  the SwiftData one) now returns every Book in no promised order, and the old
  ordering rule for Books was deleted, so the Library is the only place that
  decides the order. The SwiftData storage also lost its sort by identifier, whose
  only job was to make ties in that old rule come out the same each time; the new
  rule settles its own ties (Task 1).
- The Library screen's model keeps `libraryOrder` (Recent, Descending until the
  Library has been read), reads it together with the items at launch and on every
  reload (one failure shows the one Update the Library Notice, as before), and
  has `chooseLibraryOrder`. When the Library announces `LibraryOrderChanged`, the
  model sets `libraryOrder` and reloads, so the grid reorders. A save that fails
  shows the Notice "Couldn't Choose Library Order" with the usual "couldn't save
  the change. Try again..." message and changes nothing on screen: the Library
  Order and the items stay as they were, and no event is announced.
- Opening a Book still does not reload the grid. The two comments in the model
  that said "Library order" now say the Recent Sort.
- The app builds the Library with the SwiftData Library Order storage from Task 2.

### Tests

- Library tests: with nothing saved the Library Order is Recent, Descending;
  choosing saves it and announces it; choosing the one in force announces and
  saves nothing (shown with storage that fails every save, once with nothing
  saved and once with the same Library Order already saved); a failed save throws
  and announces nothing and the Library Order stays Recent, Descending; items
  follow Title Ascending and Date Imported Descending; a Library Order that cannot
  be read fails the list of items; opening a Book moves it under Recent and leaves
  Title alone. The error table has the Choose Library Order row.
- Model tests: choosing a Library Order reorders the items and updates
  `libraryOrder` without a Notice; the model starts with the saved one; the
  failure table asserts "Couldn't Choose Library Order" with its message; a
  separate test forces the failed save through the model and asserts the Notice,
  `libraryOrder == .initial` and the items unchanged.
- The two repository tests that asserted Library order now assert the set of
  Books returned.

### Observed

- Launch cleanup removes a Book whose folder is missing from the Books folder, so
  the first model tests (which only put Books in storage) saw an empty Library.
  The model tests now create a folder for each Book. This is existing behaviour
  of the launch step, not something this task changed.
- The plan said `NoticeTests.swift` has a `Library(` call to update; it has none
  (it only builds Notices), and its existing test of every operation's title
  already covers Choose Library Order through `allCases`. No change there.
- No new user-visible text was added: the Notice title is built from the
  operation's name, so `Localizable.xcstrings` needed no sync.
- No Apple framework behaviour is relied on by this task beyond what Task 2
  already recorded, so there are no new quotes.

### Gate

- `./scripts/test.sh`: FolioCore 107 tests in 9 suites passed (warnings as
  errors); the app's tests passed on the iOS simulator and on macOS (131 tests in
  13 suites on macOS). `./scripts/format.sh --check`: clean.
- The only build warnings are the existing "Traditional headermap style" project
  warnings.

### Not checked

- Nothing a user sees has changed (no menu yet), so nothing was launched and no
  hand check on the Mac or the simulator was done.
