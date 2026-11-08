# 2026-11-08-04: Visible Failures

**Status:** Decided

## Context

The Library slice logged many failures and showed the user nothing, so a
rename or delete that could not be saved looked like it had worked. The design
(`docs/superpowers/specs/2026-11-08-visible-failures-design.md`) made every
user action either visibly succeed or show a Notice. This log covers building
it in four tasks on `feature/visible-failures`: typed errors, failures with no
caller, Notices in `LibraryModel`, and presenting them in the Library screen.
The rulings are in `DECISIONS.md` ("Visible Failures").

## Options

| Approach | Pros | Cons |
|----------|------|------|
| Keep logging, add alerts where bugs were reported | Small change | The next unhandled failure is silent again |
| One typed `LibraryError` plus `LibraryStorageFailed` events for failures with no caller, shown as queued Notices (chosen) | The compiler forces every operation to name its failure; nothing can slip through | More cases and strings; background failures need an event |
| Show every Notice at once or replace the current one | Simple view | Loses failures or stacks alerts the system cannot show |

## Decision

Every public Library operation throws only `LibraryError` (typed throws).
Background failures become `LibraryStorageFailed(operation)` events. The model
turns both into Notices, queued and shown one at a time as a system alert, and
the codebase rule in `CLAUDE.md` requires a `// Log-only:` justification for
any catch that does not.

## Rationale

- Logging is diagnostics, not an outcome; the user needs to hear that an action failed.
- Typed throws make the rule compiler-enforced for callers instead of a review habit.
- Queueing with exact-repeat collapse avoids both lost failures and floods.

## What Changed

- `app/FolioCore/.../Library/LibraryError.swift`: `LibraryOperation` and `LibraryError`, each case carrying its operation
- `app/FolioCore/.../Library/Library.swift`: typed throws on every public operation, `storageGuard`, `LibraryStorageFailed` emission, skip set for Imports whose status cannot be saved
- `app/FolioCore/.../Domain/LibraryEvent.swift`: `libraryStorageFailed(LibraryOperation)`
- `app/FolioCore/.../Domain/FailingRepositories.swift`: repository doubles that fail on demand, for tests
- `app/Folio/Library/Notice.swift`: Notice copy for every error, storage failure, Import failure, and picker failure
- `app/Folio/Library/LibraryModel.swift`: Notice queue, `perform` per operation, DEBUG-only `FOLIO_DEBUG_NOTICES=2`
- `app/Folio/Library/LibraryView.swift`: one queued system alert; OK is the only thing that removes a Notice
- `app/Folio/Localizable.xcstrings`: new Notice strings
- `app/FolioTests/NoticeTests.swift`, `LibraryModelTests.swift`, `app/FolioCore/Tests/.../LibraryErrorTests.swift`, `LibraryTests.swift`: a forced-failure test per operation
- `CLAUDE.md`, `DECISIONS.md`: the rule, the simulator and debug-Notice notes, and the rulings

## What Was Discovered

- Typed throws enforce the contract: once `throws(LibraryError)` was on every
  public operation, any stray error type failed to compile, which is what found
  the remaining untyped paths.
- The scheduler flood: when a disk-full store refused both the In Progress and
  the Failed write, the scheduler re-picked the same Queued Import at once and
  emitted a storage event on every pass. Fixed with a per-session skip set.
- Launch could produce two or three Notices for one broken store (thrown
  `start()`, the scheduler's read, then a failing reload). The reload after a
  thrown start or a storage event is now log-only.
- SwiftUI alert hand-over: an `isPresented` binding that never flips false then
  true will not re-present the second alert, and a binding setter that removed
  a Notice could dismiss a waiting one unseen. The fix: only the OK button
  removes a Notice, the setter only hides, and the next alert is set 150 ms
  after the previous one closed.
- The task review found the file-picker error only logged; it is now a Notice.
- iOS taps do not land on the two-display "iPhone Duo" simulator (idb lacks
  SimulatorKit for this Xcode, `sim-use tap` reports success but nothing
  happens). Manual checks used a single-display iPhone 18 Pro via `SIMULATOR=`.
- Checked by hand: on macOS and on the iPhone 18 Pro simulator, two Notices
  appear one after the other, each OK removes exactly one, and the screen ends
  with no alert. Escape on macOS was not checked (keystrokes did not land).

## Log-only sites

Remaining `// Log-only:` catches (`grep -rn "Log-only:" app/`):

- `Library.swift:269`, creating the Books directory at launch: an Import that needs the directory ends Failed with its own reason.
- `Library.swift:275`, removing leftover staging: leftover staging is temporary files that nothing in the Library lists.
- `Library.swift:317`, deleting an orphan folder: a folder without a record is not listed, so it only takes up space.
- `Library.swift:428`, saving Import progress: progress is shown from events, and launch recovery resets the stored count.
- `LibraryModel.swift:67`, reload after `start()` threw: the Open the Library Notice already covers this launch failure.
- `LibraryModel.swift:79`, reload after a `LibraryStorageFailed` event: the storage Notice already covers it; a successful reload still refreshes the list.

## Follow-ups

- Untested paths: `start()` storage failure, cancel/retry/remove-Import storage failures, the `sourceNotDownloaded` mapping; the storage test fails both repositories at once, and several event tests drain only the first event while asserting equality.
- The bounded 300 ms event drains in `LibraryTests` add about 2.4 s and can miss a stray late event.
- Operation names inside Notice titles are English raw values and are not translatable; two partial-copy tests; `@MainActor` on `NoticeTests` is unnecessary.
- A Notice queued while a Rename or Delete confirmation is closing may not present (two alerts on one view); the DEBUG hook queues before the Library has loaded.
- The `.importFailed` handler reloads before queueing, so a failing reload there adds an extra Notice (same pattern as the fixed storage case).
- If SwiftUI refuses to present while another alert is closing, the view retries every 150 ms; this is unverified.
- Retrying an Import skipped for an unsaved status is not possible in-session; it needs a design decision (show it as Failed in memory).

## Results

- FolioCore: `swift test -Xswiftc -warnings-as-errors`, 81 tests in 8 suites passed.
- App tests (`build/last-test.log`, macOS run): 43 tests in 6 suites passed.
- `./scripts/verify.sh` (format, build, test, launch on iOS and macOS): green.
