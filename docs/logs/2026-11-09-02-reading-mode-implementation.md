# 2026-11-09-02: Reading Mode — implementation

**Status:** In progress (Task 2 of 5 done)

## Context

The design rulings are in `docs/logs/2026-11-09-01-reading-mode-design.md`;
the design is `docs/superpowers/specs/2026-11-09-reading-mode-design.md` and
the plan is `docs/superpowers/plans/2026-11-09-reading-mode.md`. This one log
collects what each implementation task changed, what it measured, and what it
could not check. Terms: a *stored Book* is a Book already saved on the device
by an earlier version of the app; *stand-in storage* is storage that keeps
Books in memory only and is used by tests in place of the real storage; a
*schema* is the description of how the Library's saved data is laid out on
the device, and a *migration* is the app upgrading data saved under an older
schema when it first opens it.

## Task 1: Reading Mode in FolioCore

### What Changed

- `Domain/ReadingMode.swift` (new): `ReadingMode`, either `pageByPage` or
  `vertical`.
- `Domain/Book.swift`: a Book has a `readingMode`, defaulting to
  `pageByPage`. `Book`'s decoding was written out by hand so a Book saved
  without a Reading Mode (every stored Book) decodes as Page by Page; its
  encoding is still the synthesized one, unchanged apart from the new field.
- `Domain/LibraryEvent.swift`: `readingModeChanged(BookID, mode:)`.
- `Library/LibraryError.swift`: `LibraryOperation.chooseReadingMode`
  ("Choose Reading Mode"), so a failed save can name what the user was doing.
- `Library/Library.swift`: `chooseReadingMode(bookID:_:)`, built like
  `turnPage`: it reads the Book, stops quietly if the Book already has that
  mode (no save, no event), otherwise saves and announces
  `readingModeChanged`. A failed read or save throws
  `storage(.chooseReadingMode)`; an unknown Book throws
  `notFound(.chooseReadingMode)`.
- `app/Folio/Library/LibraryModel.swift` (one word added to a list, ruling 5): `handle`
  lists `.readingModeChanged` beside `.bookOpened, .readingPositionChanged`
  so the app still compiles. It does nothing with the event yet; Task 2 does.

### Tests

- `LibraryTests`: choosing Vertical stores it and announces
  `readingModeChanged`; choosing the stored mode announces nothing and does
  not save; an unknown Book throws `notFound(.chooseReadingMode)`; a Book
  encoded without `readingMode` decodes as Page by Page and equals the
  original; a Vertical Book survives encode and decode.
- `LibraryErrorTests`: `chooseReadingMode` joins the operation switch and the
  forced-storage-failure cases (`books`, `update`), so a failing save is
  proven to throw `storage(.chooseReadingMode)`.

### What Was Discovered

- Neither stand-in storage keeps a list of the calls made to it. "Does not
  save" is therefore proven by making every Book `update` throw and showing that
  choosing the stored mode still succeeds, which it could not if it saved.
  The other `LibraryTests` events checks assert on events only.
- Test run before the code existed failed to compile (`LibraryOperation` has
  no member `chooseReadingMode`; `Library` has no member
  `chooseReadingMode`), as expected.

### Gate

- FolioCore: `swift test --package-path app/FolioCore -Xswiftc
  -warnings-as-errors`: 90 tests in 8 suites passed.
- `./scripts/build.sh macos`: build succeeded with the one-word app change.
- `./scripts/format.sh --check`: clean.
- App tests and iOS build not run for this task (the app change is the one word added to a list).

### Not checked

- No Apple documentation is relied on by this task (it is domain code only).

## Task 2: Persistence V2 and the model's log-only choose

### What Changed

- `Persistence/BookModel.swift`: the stored Book has a `readingMode` field,
  text that may be empty. Saving writes the Book's Reading Mode; reading maps
  the text back, and empty text or text that names no Reading Mode reads as
  Page by Page (the design's rule for unknown values).
- `Persistence/FolioSchema.swift`: `FolioSchemaV1` is now frozen, with its own
  copies of the two stored shapes (`FolioSchemaV1.BookModel` and
  `FolioSchemaV1.ImportModel`) inside it. `FolioSchemaV2` is the current
  schema: the same two shapes with the new field on the Book.
  `FolioMigrationPlan` lists both schemas and one stage, a *lightweight*
  migration (SwiftData carries the data across by itself because the only
  change is one added optional field; no code of ours runs) from V1 to V2.
- `Persistence/LibraryStorage.swift`: the real container is built from
  `FolioSchemaV2`. The on-disk path is now `makeContainer(at:)`, so a test can
  open a store file it wrote earlier; `makeContainer(inMemory:)` is unchanged
  for callers.
- `Library/LibraryModel.swift`: `chooseReadingMode(_:_:)` asks the Library to
  save the choice. If saving fails it is logged and no Notice is queued, with
  the owner's comment at the `catch` ("Log-only by the owner's ruling ...").
  `.readingModeChanged` was already listed in `handle` by Task 1.

### Apple documentation relied on

Fetched from `developer.apple.com/tutorials/data/documentation/swiftdata/...json`
on 2026-11-09. Apple's reference pages for these types are one-line summaries;
that is all they say:

- `VersionedSchema`: "An interface for describing a specific version of a
  schema, including the models it contains." Its `models`: "The models to
  include in this version of the schema." Its `versionIdentifier`: "The
  textual description of the migration's version or purpose." (`.../versionedschema.json`,
  `.../versionedschema/models.json`, `.../versionedschema/versionidentifier.json`)
- `SchemaMigrationPlan`: "An interface for describing the evolution of a
  schema and how to migrate between specific versions."
  (`.../schemamigrationplan.json`). Its page groups `schemas` under "Managing
  versioned schemas" and `stages` under "Managing migration stages"; the two
  members have no description text.
- `MigrationStage`: "Describes a migration between two versions of the same
  schema." (`.../migrationstage.json`). It lists `lightweight(fromVersion:toVersion:)`
  and `custom(...)` under "Migration stages"; the `lightweight` page gives only
  the signature `case lightweight(fromVersion: any VersionedSchema.Type, toVersion: any VersionedSchema.Type)`.
- `ModelContainer.init(for:migrationPlan:configurations:)`: "Creates a model
  container using the specified schema, migration plan, and zero or more
  configurations." (listed on `.../schemamigrationplan.json`)

### What the documentation does not say

Apple's pages do not say (a) that a lightweight stage covers an added optional
field, or (b) that the stored shapes may be nested inside the version enum.
Both are therefore marked as observed, and the proof is the test
`v1StoreOpensAsPageByPage`: it writes a store file on disk with the frozen V1
schema (a Book with Pages and a Reading Position, saved with the V1 copy of
the Book shape), closes it, opens the same file through the real
`makeContainer(at:)`, and checks the Book is there, unchanged, and reads as
Page by Page. It passes on macOS and on the iOS simulator.

Also observed: with the migration plan's stage list temporarily emptied, the
same test still passed, so SwiftData opened the V1 file in the V2 schema
without the stage. The stage stays, because the design and brief name it and
it states the intent; but this test proves "an old store opens", not "the
stage is what makes it open". I did not keep that probe in the code.

### Tests

- `SwiftDataRepositoriesTests`: a Book's Reading Mode roundtrips through
  storage (Vertical, then back to Page by Page); a stored Reading Mode that
  names no case reads as Page by Page; the V1 store opens in V2 (above).
- `LibraryModelTests`: choosing a Reading Mode when the Book's save fails
  queues no Notice and leaves the stored mode unchanged. It uses the same
  failing stand-in storage as the `turnPage` failure test. The existing
  failure-Notice table's `switch` gained `.chooseReadingMode` beside the other
  log-only operations (it would not compile otherwise).

### What Was Discovered

- Before the code existed the test target failed to compile (no `readingMode`
  on the stored Book, no `FolioSchemaV1.BookModel`, no `makeContainer(at:)`).
- The test run's log shows the failure path end to end: the Library throws
  `storage(.chooseReadingMode)` and logs "Could not Choose Reading Mode" under
  `AppLog.library`; the model then logs "Could not save the Reading Mode" under
  `AppLog.library` and queues nothing.

### Gate

- `./scripts/test.sh` (FolioCore 90 tests, then iOS and macOS app tests):
  every part succeeded.
- `./scripts/format.sh --check`: clean.

### Not checked

- The migration was checked with a store file written by the frozen V1 shape
  in a test, not with a store written by a build of the app that shipped V1.
- The Mac and iOS apps were not launched for this task (nothing visible
  changes yet: no screen calls `chooseReadingMode`).
