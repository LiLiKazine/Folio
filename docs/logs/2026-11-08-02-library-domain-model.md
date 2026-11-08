# 2026-11-08-02: Library and Import domain model

**Status:** Decided

## Context

The first feature slice is the Library screen plus Import. Before designing
screens or schemas, the project owner wanted a shared glossary and a
domain-driven model: aggregates, invariants, operations, events, and
repositories, with the domain isolated from SwiftUI and SwiftData.

## Options

| Approach | Pros | Cons |
|----------|------|------|
| Import as an in-memory operation; Book written on success only | Simplest; nothing to recover | Interrupted Imports vanish silently; no queue; no retry |
| Import as a persisted record with status, run one at a time from a queue (chosen) | Survives kills; retry; serial scheduling; grid derived from DB | Extra table; Source bookmark must be stored; launch recovery logic |
| Import record deleted on completion | Book keeps no trace of Source | Loses history the owner wanted to keep |

Earlier in the same session the first option was chosen and then reversed
when the owner raised persisted Imports with retry and a serial queue.

## Decision

Import is a persisted entity with status Queued, In Progress, Failed, or
Completed, kept after it ends, holding a security-scoped bookmark to its
Source. The Library runs a scheduler that promotes the oldest Queued Import
whenever none is In Progress. A Book record is written only when all its
Pages are in place. The Library grid is derived from the database (Books plus
non-Completed Imports); domain events tell the screen when to refresh.

## Rationale

- Invariant "no half Books" is kept by writing the Book last.
- Persisting the Import at creation is what makes a queue and retry possible
  and lets a killed Import resume at next launch.
- Keeping Completed Import records costs little and preserves provenance for
  the Import, while the Book itself still never refers to a Source.
- Serial scheduling bounds memory and disk churn on large zips.

## Glossary decisions

- The unit is **Book**, not Comic, so the app serves any ordered image set.
- Title comes from the picked item's own name only. A "cover" file is not
  special. Importing the same Source twice makes two Books.
- Events mirror status transitions: ImportQueued, ImportStarted,
  ImportProgressed, ImportCompleted, ImportFailed, ImportRemoved, plus
  BookRenamed, BookOpened, BookRemoved. Cancel is a Failed reason, not an
  event. "Remove" is the one verb for taking anything out of the Library.

## What Changed

- `CONTEXT.md`: new glossary with Language and Events sections
- `CLAUDE.md`: "Glossary first" rule; new concepts need owner confirmation
- `README.md`, `CLAUDE.md`: one-liner broadened beyond comics
- `docs/superpowers/specs/2026-11-08-library-and-import-design.md`: slice design

## What Was Discovered

- On iOS and in the Mac sandbox a stored path cannot reopen a picked folder;
  Retry needs a security-scoped bookmark and a "Source no longer available"
  failure reason.
- Placing the SwiftData store inside the backup-excluded Books directory
  avoids restored records with no files.
- Re-sorting the grid live when a Book is opened would shuffle cards under
  the user's finger; the order refreshes when the screen next appears.

## Implementation notes: Library actor (Task 7)

- `Library` is an actor; its scheduler is one unstructured `Task` that loops
  over Queued Imports. Cancelling the In Progress Import cancels that whole
  task, so the loop exits and immediately starts a fresh task for whatever is
  still Queued. Rejected: one task per Import (more churn for no gain) and
  per-Import child tasks (cancellation would need a separate handle map).
- A `queueChanged` flag closes a lost-wakeup gap: `createImport` can run while
  the scheduler awaits the repository and finds it empty, so the scheduler
  re-checks before going idle.
- The scheduler keeps the running Import on the actor (`running`) and decides
  `importStarted` vs `importProgressed` from whether `pagesTotal` is known yet;
  launch recovery and retry reset `pagesTotal` to nil so the next run starts
  with `importStarted`.
- `cancelImport` checks `running` after its repository read, so an Import the
  scheduler has just taken is cancelled through the task rather than being
  marked Failed underneath it.
- Launch reconciliation only touches UUID-named folders in the Books
  directory, so the SwiftData store living there is left alone.
- Review fix: the Import gets its Book id when it goes In Progress, before the
  pipeline runs. A Book added before a crash or a failed Completed write is then
  recognised at launch or on retry and the Import is marked Completed instead of
  importing a second Book. Reconciliation now runs before recovery so a Book
  record without a folder is dropped first.
- Review fix: a queue fetch already in flight when a Queued Import is cancelled
  can still return it; the actor keeps `cancelledWhileQueued` and the scheduler
  skips those ids (cleared on retry). A re-read before running was rejected
  because it relies on the repository processing writes in call order.
- Repository failures on the scheduler's queue fetch and on recording a failure
  (after one retry) are logged through `LibraryLog` (OSLog, category "library").

## Implementation notes: LibraryModel (Task 10)

- `LibraryModel` (`@Observable @MainActor`) is the only consumer of
  `Library.events`: `start()` starts the Library, loads, sets `isLoaded`, then
  iterates the stream until its task is cancelled. Tests drive it through
  `start()` and never iterate the stream themselves.
- Only `importProgressed` skips the reload (it updates `liveProgress`); every
  other change event reloads; `bookOpened` does nothing, so `open` never
  reorders the grid.
- `init(library:booksDirectory:)` takes the Books directory explicitly because
  `ImportPipeline.booksDirectory` is internal to FolioCore; the app passes
  `LibraryStorage.booksDirectory()`. Rejected: making the pipeline property
  public just for Cover lookup.
- Library errors are logged with `AppLog.library` and never thrown to the view.
