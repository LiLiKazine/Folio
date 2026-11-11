# 2026-11-11-03: Importing several Sources at once — implementation

**Status:** In progress (Task 1 of 3 done). Everything on the Mac and on a real
device is unchecked. On iPhone and iPad the picker was seen working on
simulators only.

Terms used here: the *file picker* is the system screen Folio shows so the
reader can choose Sources; the *permission to read a picked item* (Apple calls
it a security scope) is what the system gives Folio for each picked Source, which
Folio must claim before reading the Source and give back afterwards; a *test
double* is a stand-in for storage used only in tests.

## Summary

The reader can now tick several zips in the file picker and press Open once; each
zip becomes its own Import and its own Book, exactly as if it had been picked
alone. The Imports are created one after another in the order the picker hands
the Sources over, so they queue and run in that order. A Source that cannot be
referenced gets its own Notice naming it, and the Sources after it are still
imported. If the Library cannot save an Import at all, every Source is still
tried and one "Couldn't Import" Notice is shown for all of them.

What a reader notices: on iPhone, picking one zip now takes one more tap (tap the
zip to tick it, then press Open), because a picker that allows several waits for
confirmation. A folder is picked as before: go into it and press Open.

## Context

The owner keeps zips in the Files app on an iPhone and had to open the picker
once per zip. The Library already queues Imports and runs them one at a time, so
nothing changes in `FolioCore`; the model now creates an Import for each Source
handed to it. Design: `docs/superpowers/specs/2026-11-11-import-several-sources-design.md`.
Plan: `docs/superpowers/plans/2026-11-11-import-several-sources.md`.

## Task 1: The model imports several Sources; the picker allows several

### What Changed

- `app/Folio/Library/LibraryModel.swift`: `importSources(_:)` replaces
  `importSource(_:)`. It goes through the Sources in order, awaiting each before
  the next (never one task per Source). For each Source it claims the permission
  to read the picked item, creates the Import through the existing Import
  operation, and gives the permission back. A Source that fails queues the same
  Notice a single Import would, and the loop carries on.
- `app/Folio/Library/LibraryWindow.swift`: the file picker is presented with
  several allowed; every picked URL goes to the model in one task; an empty result
  (picker confirmed with nothing) does nothing. The claim and release of the
  permission moved out of the window into the model. The Mac drop target still
  hands over one Source for now (`{ importSources([$0]) }`); Task 2 changes it.
- `app/FolioTests/LibraryModelTests.swift`: every existing `importSource` call
  became `importSources([x])` with the same assertions, and five tests were added
  (below).

### Tests

New, all in `LibraryModelTests.swift`:

- several Sources become Imports in the order given, and each a Book (three
  Sources "C", "A", "B" end as Imports titled C, A, B in that order);
- a Source that cannot be referenced gets its Notice and the rest are still
  imported (First, Vol 3, Last: two Books in order and exactly one Notice naming
  "Vol 3");
- two Sources that cannot be referenced get one Notice each, in order;
- several Sources while the Library cannot save an Import give one "Couldn't
  Import" Notice and no Imports, and every Source was tried (the test double
  counts the attempts and sees three);
- no Sources does nothing: no Notice, no item, no Import created.

Red, then green: the new tests first failed to compile (`importSources` not found)
and passed once the function existed. Full suite after the change: FolioCore 107
tests, the app 139 tests on macOS (134 before), and the iOS run passed;
`./scripts/format.sh --check` clean.

### Apple documentation relied on

Fetched from `developer.apple.com/tutorials/data/documentation/`:

- `swiftui/view/fileimporter(ispresented:allowedcontenttypes:allowsmultipleselection:oncompletion:)`,
  parameter `allowsMultipleSelection`: "Whether the importer allows the user to
  select more than one file to import."
- Same page, parameter `onCompletion`: "A callback that will be invoked when the
  operation has succeeded or failed. To access the received URLs, call
  startAccessingSecurityScopedResource. When the access is no longer required, call
  stopAccessingSecurityScopedResource."
- Same page: "This dialog provides security-scoped URLs. Call the
  startAccessingSecurityScopedResource method to access or bookmark the URLs, and
  the stopAccessingSecurityScopedResource method to release the access." The
  plural "URLs" is why the claim and release happen once for each Source.
- Same page: "If the user cancels the operation, isPresented will be set to false
  and onCompletion will not be called." So cancelling the picker gives no result at
  all, and nothing happens.
- `foundation/nsurl/startaccessingsecurityscopedresource()`: "You must balance each
  call to startAccessingSecurityScopedResource() for a given security-scoped URL
  with a call to stopAccessingSecurityScopedResource()." The model gives the
  permission back for each Source it claimed, only when the claim succeeded.
- `foundation/nsurl/stopaccessingsecurityscopedresource()`: "If you call this
  method on a URL whose referenced resource you don't have access to, nothing
  happens."

### What the documentation does not say (observed)

- The order in which the picker delivers several ticked Sources is not documented.
  The design records that the spike saw zips ticked A then B delivered B then A.
  Here, ticking Alpha, Bravo and Charlie on the iPhone simulator gave Books created
  in the order Alpha, Bravo, Charlie. Folio uses whatever order arrives.
- The picker's behaviour with folders (a folder is entered, not ticked; "Select
  All" ticks zips and no folder) is as the design's spike recorded; nothing seen
  below contradicts it.

### Simulator checks

Fixtures: three zips of three Pages each (Alpha, Bravo, Charlie), one zip holding
only a text note (Empty), and a folder of three Pages (Folder Book), copied into the
simulator's "On My iPhone" / "On My iPad" storage. The Library on each simulator
already held Books from earlier work.

iPhone 17 Pro simulator, iOS 26.5:

- Ticked Alpha, Bravo and Charlie, pressed Open: three Books arrived (Alpha,
  Bravo, Charlie, three Pages each), no Notice. The Import cards were not seen: the
  three small Imports finished before the next screen read.
- Went into "Folder Book" and pressed Open: one Book, "Folder Book", three Pages.
- Ticked Alpha, Bravo and Empty, pressed Open: a Notice "Couldn't Import “Empty.zip”
  / No images found", a Failed card named "Empty" with a Retry button, and two new
  Books (Alpha and Bravo). Closing the Notice left the Library as described.
- Opened the picker and dismissed it by swiping down: nothing happened, no Notice.
- Ticked Charlie alone and pressed Open: one Book. One zip now takes a tap on the
  zip and then Open, as the design says.

iPad Pro 11-inch (M5) simulator, iOS 26.5:

- Ticked Alpha, Bravo and Charlie (a folder in the same listing did not tick),
  pressed Open: three Books arrived (Charlie, Bravo, Alpha, three Pages each).
- Went into "Folder Book" and pressed Open: one Book.

Nothing seen contradicts "What the spike found". Not seen: the Import cards while
Queued, a real device, the Mac.

### Gate

`./scripts/test.sh` passes on iOS and macOS; `./scripts/format.sh --check` clean.
`./scripts/verify.sh` runs after Task 3.

### Not checked

Everything on the Mac, a real device, VoiceOver, the Import cards while the Imports
were still waiting, an iPad folder-and-zip mix, and a picker that delivers several
folders (the design records that the Mac's picker was never tried).

## Commits

| Commit | Subject |
| --- | --- |
| c58d5b0 (main) | docs(import): the design and plan for importing several Sources at once |
| (this) | feat(import): the file picker takes several Sources and each becomes its own Import |
