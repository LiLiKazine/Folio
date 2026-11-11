# 2026-11-11-03: Importing several Sources at once — implementation

**Status:** Implemented; the owner's checks are pending. Everything on the Mac and on
a real device is unchecked. On iPhone and iPad the picker was seen working on
simulators only (see the check list).

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

On the Mac, dropping several folders and zips on the Library window imports each;
a drop holding anything that is not a folder or a zip is refused whole and springs
back, and nothing is imported.

What a reader notices: on iPhone, picking one zip now takes one more tap (tap the
zip to tick it, then press Open), because a picker that allows several waits for
confirmation. A folder is picked as before: go into it and press Open.

## Context

The owner keeps zips in the Files app on an iPhone and had to open the picker
once per zip. The Library already queues Imports and runs them one at a time, so
nothing changes in `FolioCore`; the model now creates an Import for each Source
handed to it.

A test build of the system picker on the iPhone 17 Pro simulator (iOS 26.5) showed
that tapping a zip ticks it, that two ticked zips are delivered together, that
tapping a folder enters it instead of ticking it ("Select All" ticks the zips and
no folder), that pressing Open inside a folder delivers that one folder, and that
zips ticked A then B were delivered B then A. The owner ruled: several zips ticked
for now, folders picked as before, no mixing, and the order within a visit does not
matter. The owner also ruled that when the Library cannot save an Import, one
"Couldn't Import" Notice with a fixed message is enough for every Source, and that
a Mac drop holding anything that is neither a folder nor a zip is refused whole. Design: `docs/superpowers/specs/2026-11-11-import-several-sources-design.md`.
Plan: `docs/superpowers/plans/2026-11-11-import-several-sources.md`.

## Options considered and rejected

| Question | Chosen | Rejected and why |
|----------|--------|------------------|
| Folders in the picker | Picked one at a time, as before; the system picker on iPhone and iPad does not tick folders | Ticking folders and zips in any mix: the test build showed the system picker cannot do it |
| Zips found inside a picked folder | A picked folder is still one Book of its own Pages | Looking inside it for zips: one Source would become several Books, which an Import never does |
| Order of the Imports | The order the picker or the drop delivers | Making it match the order ticked: the picker delivers in its own order and the owner said it need not match |
| The Library cannot save | Every Source is tried, one "Couldn't Import" Notice with a fixed message | Naming the Source in that Notice (new words, ten identical dialogs); stopping at the first failure (a failure would stop the rest) |
| "Zips only" | Not enforced: Folio imports whatever the picker delivers | A check or a Notice for folders: new words on screen for a case the owner did not ask to block |
| A drop with something else in it | Refused whole | Importing the folders and zips and ignoring the rest: a half-accepted drop leaves the reader guessing |

## The owner's check list

"Seen" means seen by the builder on a simulator, with the device and iOS version;
"not checked" means nobody has looked. Nothing here was checked on a real device or
on the Mac.

### iPhone

1. **Ticking several zips from the Files app on a real iPhone.** Real iPhone: not
   checked. Seen on the iPhone 17 Pro simulator (iOS 26.5): ticking three zips and
   pressing Open gave three Books with no Notice.
2. **One folder picked as before.** Seen on the iPhone 17 Pro simulator (iOS 26.5):
   going into a folder and pressing Open gave one Book of its three Pages. Real
   iPhone: not checked.
3. **One zip that fails among several.** Seen on the iPhone 17 Pro simulator (iOS 26.5):
   with two good zips and a zip holding no images ticked, the screen showed a Notice
   "Couldn't Import “Empty.zip” / No images found", a Failed card titled "Empty"
   with a Retry button, and the two good zips as new Books. Real iPhone: not
   checked.
4. **Picking exactly one zip still works.** Seen on the iPhone 17 Pro simulator (iOS 26.5):
   one Book; it takes a tap on the zip and then Open, one more tap than before. Real
   iPhone: not checked.
5. **Cancelling the picker does nothing.** Seen on the iPhone 17 Pro simulator (iOS 26.5): swiping
   the picker away changed nothing and showed no Notice. The picker's own
   Cancel and confirming with nothing ticked: not checked.
6. **The Import cards while Imports wait.** Not checked: the small test zips finished
   before the next screen read. With ten larger zips the first should show In
   Progress and the rest Queued, in the order delivered.

### iPad

7. **Ticking several zips.** Seen on the iPad Pro 11-inch (M5) simulator (iOS 26.5): three
   zips gave three Books; a folder in the same listing could not be ticked.
8. **One folder picked as before.** Seen on the iPad Pro 11-inch (M5) simulator (iOS 26.5): one Book.
9. **A failing zip among several, and picking exactly one zip, on an iPad.** Not
   checked (seen on the iPhone simulator only).

### Mac (nothing checked)

10. **The Mac's picker and File → Import… with several.** Not checked: tick several
    zips and press Open; each should become a Book. Whether the Mac's picker lets
    folders and zips be chosen together was never tried; if it does, each should
    become a Book, and nothing in Folio blocks it.
11. **Dropping several folders and zips on the Library window.** Not checked: three
    zips and a folder should give four Import cards, in the drop's order, then four
    Books.
12. **A drop with a PDF among zips.** Not checked: the drop should spring back and
    nothing should be imported, no Notice.
13. **Exactly one Source picked or dropped still works.** Not checked: one zip or one
    folder picked, and one zip or one folder dropped, each gives one Book as before.
14. **The Library unable to save.** Not checked on any device: with a full disk,
    ticking several should give no Import cards and one "Couldn't Import" Notice
    (a test forces it).

## Rulings

Each is what I decided on the owner's behalf, why, and what a user experiences if
it is wrong.

1. **One implementation log**, this file, started in Task 1's commit and extended
   by each task, although the plan creates it in Task 3. Tasks 1 and 2 had Apple
   text and simulator sightings to record before Task 3. Wrong would cost: one file
   split or merged; nothing a user sees.
2. **Commit trailers name Claude Fable 5.2 and session …3tw3CStM**, as the plan and
   the owner's prompt direct. The model that did the work is Claude Sonnet 5.5, so
   the line names a different model than the one that wrote the code. Wrong would
   cost: the three commits' trailers amended; nothing a user sees. The owner decides.
3. **No keystrokes or clicks to the Mac, and no history-erasing commands** (the
   owner's rules, kept). Wrong would cost nothing: they were kept.
4. **The "Library cannot save" test counts attempts.** The plan names the existing
   failing-storage stand-in, which cannot show that every Source was tried (three
   identical failures look the same as one). The test uses a small stand-in in the
   test file that counts how many times it was asked to save, and the test checks
   three attempts as well as one Notice and no items. Wrong would cost: a test
   rewritten; nothing a user sees.
5. **No earlier decision entry needed correcting.** The plan asks to correct the
   entry that says the Mac drop takes one Source; no entry in `DECISIONS.md` says
   it (only the code's comments did, and they were updated). Wrong would cost: one
   sentence added later; nothing a user sees.

## What was discovered

- Folio's own rule that a repeated Notice shows once is what turns "ten Sources, the
  Library cannot save" into one Notice; the test pins it with three Sources.
- A picked Source's permission to read it must be claimed and given back for each
  Source, one at a time. Apple's page speaks of "the URLs" together and does not say
  outright that each carries its own permission; that each Source needs its own claim
  and give-back is my reading of it together with the rule that every claim for a
  given URL must be balanced. The loop does exactly that and gives the permission
  back only when claiming it worked.
- The picker remembers where it was last used, including inside a folder, so a second
  visit can start there; this made the simulator checks need an extra tap and is the
  system's behaviour, not Folio's.
- The first tap on Open in an iPad check did not register when addressed by its
  label; a tap at its position worked. That is a driving detail of the simulator
  tool, not an app behaviour.
- The Mac drop's ordering of items and its spring-back are not documented on
  Apple's page and could not be seen without driving the Mac.

## Task 1: The model imports several Sources; the picker allows several

### What Changed

- `app/Folio/Library/LibraryModel.swift`: `importSources(_:)` replaces
  `importSource(_:)`. It goes through the Sources in order, awaiting each before
  the next (never started side by side). For each Source it claims the permission
  to read the picked item, creates the Import through the existing Import
  operation, and gives the permission back. A Source that fails queues the same
  Notice a single Import would, and the loop carries on.
- `app/Folio/Library/LibraryWindow.swift`: the file picker is presented with
  several allowed; every picked URL goes to the model in a single call; an empty result
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
  plural "URLs" is why I claim and release once for each Source (my reading; the
  page does not say it outright).
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
  / No images found", a Failed card titled "Empty" with a Retry button, and two new
  Books (Alpha and Bravo). Closing the Notice left the Library as described.
- Opened the picker and dismissed it by swiping down: nothing happened, no Notice.
- Ticked Charlie alone and pressed Open: one Book. One zip now takes a tap on the
  zip and then Open, as the design says.

iPad Pro 11-inch (M5) simulator, iOS 26.5:

- Ticked Alpha, Bravo and Charlie (a folder in the same listing did not tick),
  pressed Open: three Books arrived (the grid showed Charlie, Bravo, Alpha, three
  Pages each; that is the grid's order, not necessarily the order they arrived in).
- Went into "Folder Book" and pressed Open: one Book.

Nothing seen contradicts what "What the spike found" says can be ticked and
delivered. The delivery order differed from the spike's (Alpha, Bravo, Charlie
arrived in the order ticked here; the spike saw A then B arrive as B then A), which
the design already says is not guaranteed. Not seen: the Import cards while
Queued, a real device, the Mac.

### Gate

`./scripts/test.sh` passes on iOS and macOS; `./scripts/format.sh --check` clean.
`./scripts/verify.sh` was run after Task 3 (see Task 3).

### Not checked

Everything on the Mac, a real device, VoiceOver, the Import cards while the Imports
were still waiting, an iPad folder-and-zip mix, and a picker that delivers several
folders (the design records that the Mac's picker was never tried).

## Task 2: The Mac drop target takes several Sources

### What Changed

- `app/Folio/Library/LibraryDropTarget.swift`: `sources(in:)` replaces
  `source(in:)`. It returns the dropped URLs unchanged and in the order received
  when the drop is not empty and every item is a folder or a zip (the extension's
  case ignored), and nothing otherwise, so one item that is neither refuses the
  whole drop. The drop handler passes the whole list to `onImport`, now typed
  `([URL]) -> Void`. The type's comment, the function's comment and the
  modifier's comment say several. A drop that is refused returns false from the
  drop handler, as a single unsupported item always did, so it springs back and
  nothing is imported.
- `app/Folio/Library/LibraryWindow.swift`: the drop target is given
  `importSources` directly, replacing the one-Source stand-in from Task 1.
- `app/FolioTests/LibraryDropTargetTests.swift`: the tests moved to
  `sources(in:)`. "Several URLs are rejected, even if each would be a Source" was
  replaced by its opposite ("several folders and zips are Sources, in the drop's
  order"), and a new test pins that a drop holding anything else is rejected whole
  (a zip, a picture and a folder give nothing).

### Tests

Red, then green: the rewritten tests failed to compile (`sources(in:)` not found)
and passed once it existed. The suite "Library drop target" has eight tests: one
folder; one zip in any case; one that is neither; several folders and zips in
order; a drop with anything else rejected whole; a real folder without a trailing
slash; a real file with no extension rejected; an empty drop rejected. Full runs:
`./scripts/test.sh` passes on iOS and macOS (the app: 140 tests on macOS), FolioCore
107, `./scripts/format.sh --check` clean.

### Apple documentation relied on

`swiftui/view/dropdestination(for:action:istargeted:)`:

- "A closure that takes the dropped content and responds appropriately. The first
  parameter to action contains the dropped items. The second parameter contains the
  drop location in this view's coordinate space. Return true if the drop operation
  was successful; otherwise, return false." The handler returns false for a drop
  it refuses and true for one it hands over.
- "The dropped content can be provided as binary data, file URLs, or file
  promises." The drop target asks for URLs, as it did before.

### What the documentation does not say (observed)

- Whether the order of the dropped items matches the order they were arranged in
  Finder is not documented. Folio uses the order the system gives the closure.
- That a refused drop visibly springs back is not stated on that page. The design
  and a comment in the code say it does; nobody has recorded seeing it, so it is on
  the owner's list as not checked.

### Not checked

All of it. The drop target only exists on the Mac and no agent sends input to the
owner's Mac, so dropping several folders and zips, the refusal of a drop with a
picture among them, the order the Imports run in, and dropping exactly one Source
are on the owner's check list as not checked. The rule for which URLs are Sources
is covered by the unit tests above.

## Task 3: Decisions, this log and the owner's check list

### What Changed

- `DECISIONS.md`: one dated entry, in plain language, covering several Sources
  ticked or dropped at once; zips only in the picker on iPhone and iPad and why;
  one more tap for one zip; the order within a visit; a picked folder staying one
  Book; a drop with anything else refused whole; each failure keeping its own Notice
  except when the Library cannot save; and that nothing in `FolioCore` or on screen
  changed. No earlier entry said the Mac drop takes one Source, so none was
  corrected (Ruling 5).
- This log: summary, options, the owner's check list, rulings, what was discovered,
  the three tasks and the commits.

### Gate

`./scripts/verify.sh` on this branch's head after the three tasks:

```
==> green — all enabled platforms format, build, test, and launch
```

It exited 0; the test step passed on iOS and macOS (FolioCore 107 tests, the app 140
tests on macOS). The launch step starts the app on the simulator and on the Mac and
takes a screenshot; no input was sent to the Mac.

## Commits

| Commit | Subject |
| --- | --- |
| c58d5b0 (main) | docs(import): the design and plan for importing several Sources at once |
| bedcf2c | feat(import): the file picker takes several Sources and each becomes its own Import |
| aa4967d | feat(import): several folders and zips dropped on the Mac's Library window are each imported |
| 77497de | docs(import): record the decisions for importing several Sources and the owner's check list |
| (this) | docs(import): say only what Apple's page and the simulator checks support |
