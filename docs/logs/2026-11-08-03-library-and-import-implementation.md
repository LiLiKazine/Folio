# 2026-11-08-03: Library and Import implementation

**Status:** Decided

## Context

The domain model (`2026-11-08-02-library-domain-model.md`) and the slice design
were agreed; this log covers building them: thirteen tasks on
`feature/library-and-import`, from domain values to the iPad Select mode. The
implementation notes for the Library actor (Task 7), LibraryModel (Task 10), and
the Library screen (Task 11) are in the earlier log and are not repeated here.

## Options

| Approach | Pros | Cons |
|----------|------|------|
| Third-party zip package | Streaming, CRC, zip64 for free | Breaks the no-dependency rule |
| Zip reader on Compression, stored and deflate only (chosen) | No dependency; covers what zipped Sources use | In-memory entries, no CRC, no zip64 |

## Decision

Build everything on the platform: Compression for zips, ImageIO for Covers,
SwiftData for persistence, security-scoped bookmarks for Sources. Rulings made
along the way (Book id pre-assigned to an Import, stale bookmarks accepted, two
extra failure reasons, 256 MiB entry cap, the app-owned event loop, Mac bookmark
entitlements) are recorded in `DECISIONS.md`.

## Rationale

- The platform covers every need of the slice, so the no-dependency rule held.
- Keeping the domain in `FolioCore` with in-memory repositories let the Library
  scheduler, recovery, and pipeline be tested without a simulator or SwiftData.

## What Changed

- `app/FolioCore/Sources/FolioCore/Domain/`: values, events, repository protocols, in-memory repositories
- `.../Source/`: `SourceScanner`, `ZipArchive`, `Inflate`, `SourceAccess`
- `.../Import/`: `ImportPipeline`, `CoverImage`, `StorageCapacity`
- `.../Library/`: `Library` actor, `LibraryItem`, `LibraryLog`
- `app/Folio/Persistence/`: SwiftData models and repositories, `LibraryStorage`, `FileSourceAccess`
- `app/Folio/Library/`: `LibraryModel`, views, Mac commands and drop target, iPad selection bar
- `app/Config/macOS.entitlements`: bookmark and user-selected read-only entitlements
- `CLAUDE.md`, `DECISIONS.md`: architecture, conventions, and decisions for the slice

## What Was Discovered

- Compression has no CRC-32 function and no zip64; `compression_decode_buffer`
  with `COMPRESSION_ZLIB` decodes raw deflate. Decoding into a buffer one byte
  larger than the expected size catches both short and over-long streams.
- Zip names without the UTF-8 flag are CP437 by specification; a name starting
  with `/` must be rejected explicitly, since `URL.appending(path:)` places it
  under the base instead of escaping it. Archives from `ditto` and `zip` (data
  descriptors, `__MACOSX`, CJK names) extracted correctly.
- Typed throws (`throws(ZipError)`) work on the iOS 26 and macOS 26 targets.
- On macOS the first bookmark creation failed until the sandbox had the
  bookmark entitlements; the error is a vague "ScopedBookmarksAgent did not
  return error domain".
- SwiftData: `@ModelActor` repositories keep `@Model` objects inside the actor;
  status and failure reason are stored as raw strings so a `#Predicate` can
  filter them, and a raw value that no longer parses throws instead of guessing.
  Library order ties on equal timestamps are broken by id for determinism.
- `LibraryItem` collides with SwiftUI's own `LibraryItem` protocol, so views
  spell it `FolioCore.LibraryItem`.
- `xcodebuild` never writes `Localizable.xcstrings`. It was synced with
  `xcrun xcstringstool sync ... --stringsdata ...` using the stringsdata from
  both platforms (otherwise platform-only strings go stale), then compacted.
  `scripts/build.sh` builds into the default DerivedData, while `run.sh` uses
  `build/dd-*`; the stringsdata must come from the one just built.
- `./scripts/format.sh` reformats `app/FolioTests/SmokeTests.swift`; it was
  reverted and left out of every commit.
- Simulators: the gate picks a simulator by UDID; the Select mode check ran on
  an iPad simulator (iPad Pro 11-inch, iOS 26.5).
- Pages decode and the Cover renders off the main actor; `FileManager` is held
  as `nonisolated(unsafe)` in the pipeline on Apple's thread-safety guarantee.

## Gate

`./scripts/verify.sh`: green on iOS and macOS (format check, build, test,
launch with screenshot). The Mac screenshot is black because the screen is
locked; known and accepted.

Test counts: `FolioCore` 55 tests in 7 suites (run with `-warnings-as-errors`);
app target 19 tests in 5 suites on macOS.

## Manual verification still needed

- Mac (unlocked): click a card selects and does not deselect at once; double
  click opens; Delete key works after clicking a card; `Import…` with `⌘I`
  opens the picker and is disabled when the Library failed to open; dragging a
  folder or a zip from Finder starts an Import; two items or a `.png` are
  refused.
- iPad (regular width): `Select` and `Done` toggle; tapping Books toggles
  checkmarks without opening; Import cards dim and ignore taps; long press shows
  no context menu (check for a stray lift or haptic); `Delete (n)` confirms and
  removes; resizing to compact ends Select mode.
- iPhone: no Select button; tap opens; context menus work.
- Real device: import a large zip and a folder from iCloud Drive, kill the app
  mid-Import, relaunch, and confirm recovery.

## Follow-ups

- Zip reader: no CRC-32 check, no streaming (entries over 256 MiB are
  rejected), no zip64, extraction has no cancellation point, write failures
  collapse to `unreadable`; CP437 fallback and archive-comment cases untested.
- Scanner: directories with a Page extension pass the filter, the `__MACOSX`
  check scans the absolute path, redundant symlink resolution can garble the
  sort key.
- Library actor: `cancelImport` trusts a stale status read and can strand a
  Queued record if its Failed write throws; a cancel arriving after the
  pipeline returns is lost; `createImport` before `start()` runs the scheduler
  before recovery; `Library.swift` is over 300 lines.
- Source access: refresh and persist stale bookmarks; some Foundation errors
  surface raw instead of as `SourceAccessError`.
- Pipeline: Cover write failures report `undecodablePage` and ENOSPC during zip
  extraction reports `unreadableZip`; an empty `.staging` folder is left behind.
- UI: no keyboard way to open a Book on Mac; the drop highlight shows for any
  dragged item; `⌘I` may collide with Italic later; selection cards lack the
  selected accessibility trait on iPad; alert titles can flash a stale count
  while animating out; two reloads at launch; the storage-failure screen is
  plain text; if the first window closes the multi-window story is untested.
- Tests: SwiftData on-disk container path, iCloud download polling, and
  `liveProgress` updates are untested.
- `bookID` on an In Progress or Failed Import points at no Book; no code may
  treat it as "has a Book".
