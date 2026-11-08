# 2026-11-08-04: Visible Failures

**Status:** Decided

## Context

The Library slice logged many failures and showed the user nothing, so a
rename or delete that could not be saved looked like it had worked. The design
(`docs/superpowers/specs/2026-11-08-visible-failures-design.md`) made every
user action either visibly succeed or show a Notice. This log covers building
it in four tasks on `feature/visible-failures`: typed errors, failures with no
caller, Notices in `LibraryModel`, and presenting them in the Library screen.
The rulings, including the process ruling that Task 3 could make the minimal Library screen edit so the app kept compiling, are in `DECISIONS.md` ("Visible Failures"). Terms used below: an *event* is one of the announcements the Library makes when something changes (listed under Events in `CONTEXT.md`); the *store* is the database file where Books and Imports are saved; the *Import scheduler* is the part of the Library that runs Queued Imports one after another; *launch recovery* is the step at launch that puts interrupted Imports back in the queue and tidies leftover records; the *launch step* is the Library's start-up call, `start()`, which runs launch recovery; a *catch* is the code that handles a failed step; *logging* is writing a line to the system's diagnostic log, which the user never sees; *SwiftUI* is Apple's screen-building framework; a *binding* is SwiftUI's two-way link between a value and what is on screen; a *skip set* is a list of Imports the scheduler has been told to leave alone; *in memory* means held only while the app runs, not saved.

## Options

| Approach | Pros | Cons |
|----------|------|------|
| Keep logging, add a Notice only where a bug was reported | Small change | The next unhandled failure is silent again |
| One typed `LibraryError` plus `LibraryStorageFailed` events for failures with no caller, shown as queued Notices (chosen) | The compiler forces every operation to name its failure; nothing can slip through | More cases and strings; background failures need an event |
| Show every Notice at once or replace the current one | Simple view | Loses failures or stacks dialogs the system cannot show |

## Decision

Every public Library operation throws only `LibraryError` (typed throws, the compiler feature that lets a function declare exactly which error type it can raise).
Background failures become `LibraryStorageFailed(operation)` events. The model
turns both into Notices, queued and shown one at a time in a system dialog, and
the codebase rule in `CLAUDE.md` requires a `// Log-only:` justification for
any catch that does not.

## Rationale

- Logging is diagnostics, not an outcome; the user needs to hear that an action failed.
- Typed throws make the rule compiler-enforced for callers instead of a review habit.
- Queueing with exact-repeat collapse (a Notice identical to the one just queued is not added again) avoids both lost failures and floods.

## What Changed

- `app/FolioCore/.../Library/LibraryError.swift`: `LibraryOperation` and `LibraryError`, each case carrying its operation
- `app/FolioCore/.../Library/Library.swift`: typed throws on every public operation, `storageGuard`, `LibraryStorageFailed` emission, skip set for Imports whose status cannot be saved
- `app/FolioCore/.../Domain/LibraryEvent.swift`: `libraryStorageFailed(LibraryOperation)`
- `app/FolioCore/.../Domain/FailingRepositories.swift`: repository doubles that fail on demand, for tests
- `app/Folio/Library/Notice.swift`: Notice copy for every error, storage failure, Import failure, and picker failure
- `app/Folio/Library/LibraryModel.swift`: Notice queue, `perform` per operation (the model's helper that runs an operation and turns any failure into a Notice), `FOLIO_DEBUG_NOTICES=2`, which only works in DEBUG builds (the developer builds that never ship)
- `app/Folio/Library/LibraryView.swift`: one queued system dialog; OK is the only thing that removes a Notice
- `app/Folio/Localizable.xcstrings`: new Notice strings
- `app/FolioTests/NoticeTests.swift`, `LibraryModelTests.swift`, `app/FolioCore/Tests/.../LibraryErrorTests.swift`, `LibraryTests.swift`: a forced-failure test per operation
- `CLAUDE.md`, `DECISIONS.md`: the rule, the simulator and debug-Notice notes, and the rulings

## What Was Discovered

- Typed throws enforce the contract: once `throws(LibraryError)` was on every
  public operation, any stray error type failed to compile, which is what found
  the remaining untyped paths.
- The Import scheduler flood: when a disk-full store refused both the In Progress and
  the Failed write, the scheduler re-picked the same Queued Import at once and
  emitted a `LibraryStorageFailed` event on every pass. Fixed with a per-session skip set.
- Launch could produce two or three Notices for one broken store (the launch
  step `start()` throwing, the Import scheduler's read failing, then a failing
  reload of the Library list). The reload after a throwing launch step or after
  a `LibraryStorageFailed` event is now log-only.
- SwiftUI dialog hand-over: an `isPresented` binding that never flips false then
  true will not show the second Notice, and a binding setter that removed
  a Notice could remove a waiting one unseen. The fix: only the OK button
  removes a Notice, the setter only hides, and the next dialog is set 150 ms
  after the previous one closed.
- The task review found the file-picker error only logged; it is now a Notice.
- iOS taps do not land on the two-display "iPhone Duo" simulator (idb, a simulator control tool, lacks
  SimulatorKit, a simulator library, for this Xcode; `sim-use tap`, a simulator tap tool, reports success but nothing
  happens). Manual checks used a single-display iPhone 18 Pro via `SIMULATOR=`.
- Checked by hand: on macOS and on the iPhone 18 Pro simulator, two Notices
  appear one after the other, each OK removes exactly one, and the screen ends
  with no dialog.

## Log-only sites

Remaining `// Log-only:` catches (`grep -rn "Log-only:" app/`):

- `Library.swift:269`, creating the Books directory at launch: an Import that needs the directory ends Failed with its own reason.
- `Library.swift:275`, removing leftover staging: leftover staging is temporary storage that nothing in the Library lists.
- `Library.swift:317`, deleting an orphan folder: a folder without a record is not listed, so it only takes up space.
- `LibraryModel.swift:67`, reload after the launch step (`start()`) threw: the Open the Library Notice already covers this launch failure.
- `LibraryModel.swift:79`, reload after a `LibraryStorageFailed` event: the storage Notice already covers it; a successful reload still refreshes the list.

Calls whose failure is discarded without logging (`try?`, Swift's way of throwing an error away) carry `// Ignored:` with the reason instead (`grep -rn "Ignored:" app/`): the progress count save in `Library.swift`, staging removal in `ImportPipeline.swift`, closing a read-only zip in `ZipArchive.swift`, the folder check in `LibraryDropTarget.swift`, and the hand-over delay in `LibraryView.swift` and the DEBUG test hook in `LibraryModel.swift`.

## Manual verification still needed

- The Escape key on the Mac removing a Notice (keystrokes did not land in the check).
- A file-picker failure Notice appearing while the picker itself is still closing.

## Follow-ups

- Untested paths: the launch step (`start()`) failing to read Imports, cancel/retry/remove-Import storage failures, the reason given when a Source has not finished downloading from iCloud (`sourceNotDownloaded`); the storage test fails both the Book and Import stores at once, and several event tests drain only the first event while asserting equality.
- The bounded 300 ms event drains in `LibraryTests` (waits of 300 ms that collect events during a test) add about 2.4 s and can miss an event that arrives late.
- Operation names inside Notice titles are English raw values and are not translatable; two tests that check only part of a Notice's text; an unneeded `@MainActor` (the marker that keeps a type on the screen's thread) sits on `NoticeTests`.
- The test hook for DEBUG builds (`FOLIO_DEBUG_NOTICES=2`) queues before the Library has loaded.
- The `.importFailed` handler (the code that reacts to an ImportFailed event) reloads before queueing, so a failing reload there adds an extra Notice (same pattern as the fixed storage case).
- The view does not retry a refused Notice dialog. It avoids the known refusal (another dialog on the Library screen is open) by waiting until that dialog closes, then hands over after 150 ms; a refusal for any other reason would leave Notices unshown until relaunch.
- Retrying an Import skipped for an unsaved status is not possible in-session; it needs a design decision (show it as Failed in memory).

## Gate

- FolioCore: `swift test` with every compiler warning treated as a failure (`-Xswiftc -warnings-as-errors`), 81 tests in 8 suites passed.
- App tests (`build/last-test.log`, macOS run): 43 tests in 6 suites passed.
- `./scripts/verify.sh` (format, build, test, launch on iOS and macOS): green.
