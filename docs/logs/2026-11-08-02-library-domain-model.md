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
