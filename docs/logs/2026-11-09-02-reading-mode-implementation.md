# 2026-11-09-02: Reading Mode — implementation

**Status:** In progress (Task 1 of 5 done)

## Context

The design rulings are in `docs/logs/2026-11-09-01-reading-mode-design.md`;
the design is `docs/superpowers/specs/2026-11-09-reading-mode-design.md` and
the plan is `docs/superpowers/plans/2026-11-09-reading-mode.md`. This one log
collects what each implementation task changed, what it measured, and what it
could not check. Terms: a *stored Book* is a Book already saved on the device
by an earlier version of the app; a *call record* is a list a test double
keeps of the calls made to it.

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
- `app/Folio/Library/LibraryModel.swift` (one token, ruling 5): `handle`
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

- Neither repository test double has a call record. "Does not save" is
  therefore proven by making every Book `update` throw and showing that
  choosing the stored mode still succeeds, which it could not if it saved.
  The other `LibraryTests` events checks assert on events only.
- Test run before the code existed failed to compile (`LibraryOperation` has
  no member `chooseReadingMode`; `Library` has no member
  `chooseReadingMode`), as expected.

### Gate

- FolioCore: `swift test --package-path app/FolioCore -Xswiftc
  -warnings-as-errors`: 90 tests in 8 suites passed.
- `./scripts/build.sh macos`: build succeeded with the one-token app change.
- `./scripts/format.sh --check`: clean.
- App tests and iOS build not run for this task (app change is the one token).

### Not checked

- No Apple documentation is relied on by this task (it is domain code only).
