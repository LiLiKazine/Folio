# Importing Several Sources at Once — Design

Date: 2026-11-11
Status: ready for approval (revised after the builder check and a spike of the picker)
Glossary: `CONTEXT.md` is authoritative. Capitalised terms are glossary terms.
Builds on: `2026-11-08-library-and-import-design.md` (Imports, their queue,
the file picker, the Mac drop target) and
`2026-11-08-visible-failures-design.md` (a failed action shows a Notice).

## Intent

The owner keeps zips in the Files app on an iPhone. To bring several into the
Library they must open the file picker once per zip, because the picker lets
them tick only one Source. The Library already queues Imports and runs them
one at a time; what is missing is a way to hand it several Sources in one go.
This slice lets the reader tick several Sources in the file picker, and drop
several on the Mac's Library window.

## What the owner decided (this conversation)

- **Ticking several zips in the file picker**, confirmed once. A folder is
  picked the way it always was, one per visit. The owner first asked for
  zips and folders in any mix; a spike showed the system picker on iPhone
  does not tick folders (see "What the spike found"), and the owner ruled:
  several zips for now, folders as before, no mixing.
- **The order within one visit does not matter.** The Imports are created in
  whatever order the picker delivers, which the spike showed is not the
  order ticked.
- **Not the folder-of-zips case.** A picked folder still becomes one Book
  made of its own Pages. Folio does not look inside it for zips.
- **Dropping several on the Mac's Library window** is accepted too.
- **One Import and one Book per Source**, as if each had been picked alone.
- **Each failure gets its own Notice**, naming its Source, as today.
- **One exception, ruled after the builder check: when the Library cannot
  save an Import at all** (the disk is full, say), every Source handed over
  fails the same way. That Notice is "Couldn't Import" with a fixed message
  and no Source name, and the existing rule shows a Notice once when it
  repeats the one before it. So several Sources give no Import cards and one
  Notice. The owner accepted this: the problem is the Library, not any one
  Source, and one Notice says so. Rejected: naming the Source in that Notice
  (new on-screen words, ten identical dialogs), and stopping at the first
  save failure (contradicts "a failure does not stop the rest").
- **No limit** on how many Sources are picked or dropped.
- **A drop that contains anything that is not a folder or zip is refused
  whole** and springs back, as a single unsupported item does today.
- **iPhone and iPad get no drop target** in this slice; they have none today.
- **No glossary change.** An Import is still one Source becoming one Book.

## Calls made by the designer

The owner agreed these; they are listed so they can be checked.

- **Order.** The Imports are created one after another in the order the
  picker or the drop delivers the Sources, so they queue and run in that
  order. The owner ruled that this order need not match the order ticked.
- **Nothing in Folio enforces "zips only".** The limit is the system
  picker's: on iPhone it will not tick a folder. Folio hands the Library
  whatever the picker delivers, one Import per Source. If a picker on
  another platform delivers several folders or a mix (the Mac's was not
  tried), each still becomes its own Import. Refusing them would need a new
  Notice and new on-screen words for a case the owner did not ask to block.
- **Picking one zip takes one more tap on iPhone.** With several allowed, a
  tap ticks the zip and Open confirms; today a tap imports it at once. This
  comes with the system picker and was reported to the owner with the
  spike's findings.
- **The Mac drop is unchanged by the spike**: several folders and zips, in
  any mix, as agreed. It does not go through a picker.
- **A failure does not stop the rest.** If a Source cannot be referenced
  (it is unavailable, or not downloaded), its Notice is queued and the next
  Source is still handed to the Library.
- **Two Notices that say exactly the same thing still show once.** The
  existing rule drops a Notice that repeats the one queued just before it.
  Two Sources with the same file name failing the same way would therefore
  show one Notice. Accepted; it is today's rule.
- **No new on-screen words.** The Import button, its Mac tooltip ("Import a
  folder or zip") and the File → Import… command keep their copy.

## What the spike found

A throwaway build with the picker allowed to take several, on the iPhone 17
Pro simulator, iOS 26.5. The change was reverted afterwards.

- Tapping a zip ticks it; two ticked zips were delivered together and both
  became Books.
- Tapping a folder opens it and does not tick it. "Select All" ticked the
  zips and no folder.
- A folder is picked as today: go into it and press Open, which delivers
  that one folder. With a zip ticked and a folder then entered, Open
  delivered one of them, never both.
- With several allowed, one zip needs a tap and then Open. Today a tap on a
  zip imports it at once (seen on the same simulator with the unchanged
  build).
- Zips ticked A then B were delivered B then A.

Not tried: an iPad, a real device, the Mac's picker.

## Goals

- In the file picker on iPhone, iPad and Mac the reader can tick several
  zips and confirm once; a folder is picked as before. The Mac's File → Import… command opens the same
  picker, so it gains this with no change of its own.
- On the Mac, dropping several folders or zips on the Library window imports
  each.
- Each Source ticked or dropped appears as its own Import card at once
  (Queued, or In Progress for the first), in the order delivered.
- Picking one folder, and dropping exactly one Source, behave as they do
  today. Picking one zip gives the same result with one more tap.

## Non-goals

- Importing the zips found inside a picked folder.
- Ticking several folders, or folders together with zips, in the picker on
  iPhone or iPad. The system picker does not allow it.
- Making the Imports' order match the order ticked.
- A drop target on iPhone or iPad.
- One combined Notice for several failures, or a summary when all are done.
- Running Imports in parallel. They still run one at a time.
- A limit, or a warning, for many Sources.
- Cancelling or retrying several Imports at once.

## Anti-goals

- A Source that was ticked or dropped and then neither appears as an Import
  nor is covered by a Notice. (When the Library cannot save, one Notice
  covers every Source handed over; see the exception above.)
- Imports that run in a different order from the one the picker or the drop
  delivered.
- A drop that is half accepted: some items imported, others silently
  ignored.

## Behaviour

- **Ten zips ticked, all good.** Ten Import cards appear, the first In
  Progress and nine Queued, in the picker's order. Ten Books arrive one after
  another.
- **Ten ticked, three cannot be referenced.** Seven Import cards appear and
  three Notices are queued, one per Source, each naming its Source. They are
  dialog Notices, shown one after another as the reader closes each.
- **Ten ticked, one has no images inside.** Ten cards appear; that Import
  ends Failed with its Notice when its turn comes, and the rest carry on.
  This is today's behaviour for any Import and does not change.
- **Ten ticked while the Library cannot save.** No cards appear and one
  "Couldn't Import" Notice is shown. Every Source is still tried.
- **The same zip ticked today and again tomorrow.** Two Imports and two
  Books, the existing rule.
- **The picker is cancelled, or confirmed with nothing ticked.** Nothing
  happens.
- **The picker itself fails.** The existing file-picker Notice, once.
- **Mac: three zips and a folder dropped.** Four Imports, in the drop's
  order.
- **Mac: two zips and a PDF dropped.** The drop is refused and springs back;
  nothing is imported.
- **An Import is running when more Sources are ticked.** The new Imports
  queue behind what is already Queued, as a single new Import does today.

## Architecture

No change in FolioCore: `Library.createImport(from:)` already creates one
Queued Import per call and the scheduler already runs them in creation order.

### App: Library

- `LibraryModel` gains

  ```swift
  /// Creates one Import per Source, in order. Each Source's security scope is
  /// held while its Import is created. A Source that fails queues its Notice
  /// and the rest are still handed to the Library.
  func importSources(_ urls: [URL]) async
  ```

  It replaces `importSource(_:)`. The `startAccessingSecurityScopedResource`
  / `stopAccessingSecurityScopedResource` pair that `LibraryWindow` wraps
  around today's call moves into it, once per Source, so the order and the
  per-Source failure rule can be tested without a window. The Sources are
  handled one after another, each awaited before the next, never in separate
  tasks: that is what makes the Imports' creation order the order handed
  over.
- `LibraryWindow`: the file importer is opened with
  `allowsMultipleSelection: true`; `importPicked` hands every picked URL to
  `model.importSources` in one task; an empty result does nothing. The
  window's own `importSource(_:)` becomes `importSources(_:)`.
- `LibraryDropTarget` (Mac): `source(in:)` becomes

  ```swift
  /// The Sources in a drop, in the drop's order, or nil when the drop is empty
  /// or holds anything that is not a folder or zip.
  nonisolated static func sources(in urls: [URL]) -> [URL]?
  ```

  `onImport` takes `[URL]`. The type's comment and `libraryDropTarget`'s are
  updated to say several.

The builder reads Apple's documentation for `fileImporter` with
`allowsMultipleSelection: true`, quotes what it says about choosing several
items and about each returned URL carrying its own security scope, and
records it in the log. Where the documentation is silent, the builder says
what was observed on the simulator.

The spike already answered how the picker behaves on an iPhone simulator.
**If the builder sees anything that contradicts "What the spike found"** (on
the iPad simulator, say, a folder that cannot be picked at all, or several
ticked zips of which only one is delivered), **the builder stops and reports
to the owner; it does not choose a fallback.**

## Tests

- `LibraryModel.importSources`:
  - three good Sources end as three items in the order given (assert on the
    Import items' Titles before any completes, using a held Source access as
    the existing tests do, or on creation order);
  - a list where the middle Source cannot be referenced gives two Imports,
    in order, and exactly one Notice naming the middle Source;
  - two Sources that both cannot be referenced, with different names, give
    two Notices in order;
  - three Sources while the Import repository cannot save: no Import items,
    and exactly one Notice, "Couldn't Import" with the save-failure message
    (the project's rule: every operation has a test that forces its failure
    and asserts the Notice);
  - an empty list does nothing;
  - one Source behaves as the existing single-Source tests assert. Those
    tests move to the new function.
- `LibraryDropTarget.sources(in:)`: one folder; one zip in any case; several
  folders and zips come back in order; any item that is neither makes the
  whole drop nil; an empty drop is nil; a real folder without a trailing
  slash counts; a real file with no extension makes it nil. The existing
  test "several URLs are rejected, even if each would be a Source" is
  replaced by its opposite.

## Checks the builder runs

On an iPhone simulator: put several zips in the Files app, open the picker,
tick three and confirm; see three cards and three Books. Go into a folder
and press Open; see one card and one Book. Tick several zips that include
one with no images; see its Failed card and Notice and the
others' Books. Tick one only; behaves as before. Repeat the first check on
an iPad simulator. Record the device, the iOS version and what was seen.

Nothing on the Mac is driven by an agent. The Mac picker, the File → Import…
command and the drop go on the owner's check list as not checked.

## Constraints

- Swift 6 strict concurrency; SwiftUI only; no third-party dependencies.
- `./scripts/verify.sh` green on every platform; warnings are errors.
- Glossary terms exactly; none of the _Avoid_ words (for Import: "add",
  "open", "load", "upload", "task", "job"; for Source: "original", "file",
  "archive").
- Designs rest on Apple's documentation; no timers, delays or guards around
  undocumented timing.

## Decision log entries this slice must add

In `DECISIONS.md`, in plain language: several Sources can be ticked or
dropped at once and each becomes its own Import; a picked folder is still
one Book and its zips are not looked into; a drop holding anything else is
refused whole and why; each failure keeps its own Notice, except that a
Library that cannot save shows one Notice for all of them, and why. The earlier entry
that says the Mac drop takes one Source is corrected.

## The owner's check list

The builder writes one in the decision log, covering at least: ticking
several zips on a real iPhone from the Files app; one folder picked as
before; one zip that fails among several; whether the Mac's picker lets
folders and zips be chosen together, and that each becomes a Book if it
does; the Mac picker and File → Import… with
several; dropping several on the Mac; a drop with a PDF among zips springs
back; picking exactly one still works on each platform.

## Left to the builder

- Whether `importSources` is reached through `perform(.import)` once per
  Source, as today, or through a small helper; the Notices must be the ones
  today's single Import produces.
- How the order test observes creation order.
