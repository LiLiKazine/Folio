# Presentation Coordinator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Library screen presents one dialog at a time from a single source of truth, advancing only on SwiftUI's documented dismissal; background Notices become a status line; the workaround layer and test scaffolding are deleted.

**Architecture:** A pure `PresentationQueue` (current + pending) is the only state the view's dialog modifiers read. Every request (Notice dialog, picker, Rename, Delete, multi-delete) is enqueued; each modifier's binding is derived from `queue.current` and its setter on `false` calls `queue.dismissed(id)`. `Notice` gains a `kind` (`.dialog` for failures of a user action, `.status` for background failures); the view shows `.status` Notices as a nonintrusive line above the grid. `FOLIO_DEBUG_NOTICES`, `handledEventCount`, `ImportRequestGate`, `isSettling`, `isPresentingOtherDialog`, `shownNotice`, and the per-dialog flags are removed.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, Swift Testing. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-08-presentation-coordinator-design.md` (glossary `CONTEXT.md`; amends `docs/superpowers/specs/2026-11-08-visible-failures-design.md` with a Presentation column)

## Global Constraints

- `CONTEXT.md` terms exactly; never `_Avoid_` words ("alert", "toast", "banner", "dismissed" for a Notice/ImportRemoved; "file", "image", "progress" for glossary concepts). "Presentation", "status line", "Dismissed" are mechanisms defined in the spec.
- Swift 6 strict concurrency, warnings as errors; Swift Testing only; OSLog only; strings localizable and the catalog synced as in `docs/logs/2026-11-08-03-library-and-import-implementation.md`.
- No timers, no delays, no polling in the presentation path. The only transition is SwiftUI's write-back of the binding to `false`.
- No test scaffolding in the app target (no debug env hooks, no test-only counters).
- Notice copy unchanged. Exact-repeat collapsing in `LibraryModel.queue(_:)` stays.
- Commands: `./scripts/test.sh macos` to iterate, `./scripts/verify.sh` as the gate (both platforms), `./scripts/format.sh --check` clean. Commit after each task in the structured format with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01LmeQ4kF6jaBLLT9tw3CStM`.

## Review Focus

1. Two Notices back to back: the second must present after the first is dismissed on iOS 26 and macOS 26. Manual check by the owner (Task 4 lists it); if it fails, report, do not add a delay.
2. ⌘I while a Notice dialog is showing: the picker must open after the Notice closes. Owner's manual check.
3. A `.status` Notice must never present as a dialog, including at launch. Unit test in Task 2; visual check in Task 4.
4. The iPad multi-delete must delete exactly the Books selected when Delete was tapped, even if the selection changes afterwards. Unit test on the captured set in Task 3.
5. Removing `handledEventCount` must not make any model test vacuous or flaky: each adapted test waits on real state. Review in Task 2.

---

## File Structure

- Create `app/Folio/Library/Presentation.swift`: `Presentation` enum and `PresentationQueue`.
- Create `app/FolioTests/PresentationQueueTests.swift`.
- Modify `app/Folio/Library/Notice.swift`: `kind`.
- Modify `app/Folio/Library/LibraryModel.swift`: `kind` assignment; remove `handledEventCount` and `queueDebugNotices`; add `statusNotice`/`dismissStatusNotice` if `.status` Notices are kept in a separate slot (builder's call: one queue filtered by kind is acceptable).
- Modify `app/FolioTests/LibraryModelTests.swift`: adapt tests that used `handledEventCount`; add kind tests.
- Modify `app/Folio/Library/LibraryView.swift`: queue-driven presentation; delete flags and gate; status line.
- Create `app/Folio/Library/LibraryStatusLine.swift`: the nonintrusive line.
- Modify `app/Folio/Library/LibraryCommands.swift`: focused value becomes a request action.
- Modify `app/Folio/Library/LibrarySelectionBar.swift` only if its API must carry the captured ids.
- Delete `app/Folio/Library/ImportRequestGate.swift`, `app/FolioTests/ImportRequestGateTests.swift`.
- Docs: Visible Failures spec (Presentation column), `DECISIONS.md`, `CLAUDE.md` (remove the `FOLIO_DEBUG_NOTICES` paragraph), `docs/logs/2026-11-08-05-presentation-coordinator.md`.

---

### Task 1: PresentationQueue

**Files:** Create `app/Folio/Library/Presentation.swift`; Test `app/FolioTests/PresentationQueueTests.swift`.

**Interfaces:**
```swift
enum Presentation: Equatable, Identifiable, Sendable {
    case notice(Notice)
    case importPicker
    case rename(Book)
    case deleteBook(Book)
    case deleteSelection(Set<BookID>)
    var id: String   // "notice:<uuid>", "picker", "rename:<uuid>", "delete:<uuid>", "deleteSelection:<sorted uuids joined>"
}
struct PresentationQueue: Equatable, Sendable {
    private(set) var current: Presentation?
    private(set) var pending: [Presentation]
    init()
    mutating func enqueue(_ p: Presentation)        // current if idle, else appended; nothing filtered
    mutating func dismissed(_ id: Presentation.ID)  // clears current if ids match and promotes pending.first; stale id ignored
}
```

- [ ] **Step 1: Write the failing tests** — `enqueueWhenIdlePresents`, `enqueueWhenBusyQueuesInOrder`, `dismissedPromotesNext`, `staleDismissedIgnored`, `mixedSequenceInOrder` (Notice, picker, rename, Notice), `dismissedWithEmptyPendingLeavesIdle`.
- [ ] **Step 2: Run** `./scripts/test.sh macos` → compile failure.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** → `** TEST SUCCEEDED **`.
- [ ] **Step 5: Commit** `feat(library): PresentationQueue, one dialog at a time by construction`.

---

### Task 2: Notice kind; remove the test seam and the debug hook from the model

**Files:** Modify `Notice.swift`, `LibraryModel.swift`, `LibraryModelTests.swift`.

**Interfaces:**
```swift
extension Notice { enum Kind: Sendable, Equatable { case dialog, status }; let kind: Kind }
// Notice(error:) and Notice(importFailed:reason:) and filePickerFailed() → .dialog
// Notice(storageFailed:) → .status   (LibraryStorageFailed events; launch and reload failures)
```
`LibraryModel`: `handledEventCount` and `queueDebugNotices()` (and its call) removed. `presentedNotice` returns the first `.dialog` Notice; new `statusNotice: Notice?` returns the first `.status` Notice; `dismissNotice(_:)` removes by id for either kind. Exact-repeat collapse unchanged.

- [ ] **Step 1: Failing tests** — `storageFailedIsStatus`, `actionFailuresAreDialog`, `statusAndDialogPresentedSeparately` (queue one of each; `presentedNotice` is the dialog one, `statusNotice` the status one), and adapt every test that used `handledEventCount` (LibraryModelTests ~251, 256, 277, 290, 326-339, 620) to wait on real state (`items`, `notices`, `statusNotice`, or the Library actor's own records) with the existing deadline helper. For `openNoReorder`, wait until the Library actor reports the Book's `lastOpenedAt` is set, then wait a bounded 300 ms and assert `items` order is unchanged; say in a comment that this is a bounded negative check.
- [ ] **Step 2: Run** → failures/compile errors.
- [ ] **Step 3: Implement.** `grep -rn "handledEventCount\|FOLIO_DEBUG_NOTICES" app/` must be empty afterwards.
- [ ] **Step 4: Run** `./scripts/test.sh macos` three times (flakiness) → green each time.
- [ ] **Step 5: Commit** `feat(library): Notice kind splits dialog and status; drop test scaffolding from the model`.

---

### Task 3: Queue-driven Library screen and status line

**Files:** Modify `LibraryView.swift`, `LibraryCommands.swift`, `LibrarySelectionBar.swift` (if needed); Create `LibraryStatusLine.swift`; Delete `ImportRequestGate.swift` and its tests; sync `Localizable.xcstrings` if strings changed.

**Interfaces / rules:**
- `@State private var queue = PresentationQueue()` is the only presentation state. Helpers: `func request(_ p: Presentation) { queue.enqueue(p) }` and `private func binding(for match: @escaping (Presentation) -> Bool) -> Binding<Bool>` whose getter is `queue.current.map(match) ?? false` and whose setter on `false` calls `queue.dismissed(queue.current!.id)` when the current matches.
- One `.fileImporter(isPresented: binding(for: { $0 == .importPicker }) …)`; one `.alert` for the Notice dialog (`presenting:` the Notice from `queue.current`); one Rename alert; one Delete confirmation; one multi-delete confirmation (iOS). Each dialog's buttons do their work; SwiftUI's write-back drives `dismissed`. The Notice dialog's `OK` and its dismissal both call `model.dismissNotice(id)`.
- `.onChange(of: model.presentedNotice?.id, initial: true)`: when non-nil and not already current/pending, `request(.notice(n))`.
- Toolbar plus, empty-state button, ⌘I: `request(.importPicker)`. `LibraryCommands`' focused value becomes `Binding<Bool>` whose setter calls `request(.importPicker)` (same key, documented), or an action closure; builder's call, keep ⌘I disabled when no Library is focused.
- Context menu Rename/Delete: `request(.rename(book))`/`request(.deleteBook(book))`. iPad Select-mode Delete: `request(.deleteSelection(selectedBookIDs))`; the confirmation title count and the deletion use the captured set.
- Status line: `LibraryStatusLine(notice:onClose:)` shown above the grid when `model.statusNotice != nil`; close calls `model.dismissNotice(id)`. Plain text (title and message), a close control, HIG-compliant, no animation that shifts the grid abruptly (builder's call).
- Delete: `isImporting`, `bookToRename`, `bookToDelete`, `isConfirmingDeleteSelection`, `shownNotice`, `isSettling`, `settleTask`, `importRequest`, `isPresentingOtherDialog`, `canPresentImport`, `showPresentedNotice`, `settleAfterDialogs`, `ImportRequestGate` and its tests. `renameTitle` stays (seeded when `.rename` becomes current, via `onChange(of: queue.current?.id)`).

- [ ] **Step 1: Implement.** `grep -n "isSettling\|ImportRequestGate\|isPresentingOtherDialog\|shownNotice" app/` must be empty.
- [ ] **Step 2: Unit test** on the captured selection: a small test that builds `.deleteSelection(ids)` and asserts the id string is stable for the same set (ordering independent). Existing `LibraryDropTargetTests` unchanged.
- [ ] **Step 3: Gate** `./scripts/verify.sh` green on both platforms; sync the catalog if strings changed.
- [ ] **Step 4: Commit** `feat(library): present dialogs from one PresentationQueue; status line for background Notices`.

---

### Task 4: Docs and owner's manual check list

**Files:** Modify Visible Failures spec (add a "Presentation" column: `dialog` for the action rows and the Import-failure row; `status line` for the LibraryStorageFailed row and the Open/Update the Library rows), `DECISIONS.md` (one dated section, plain language: why one source of truth, why no delays, why background Notices are a status line per HIG, what was removed and why it was a workaround), `CLAUDE.md` (remove the `FOLIO_DEBUG_NOTICES` paragraph; keep the single-display-simulator note), create `docs/logs/2026-11-08-05-presentation-coordinator.md` (format of the previous logs; include the documentation quotes the design rests on, the list of removed code, and the owner's manual check list: on Mac, iPhone, iPad: ⌘I/plus while a Notice is showing then close it → picker; two Notices in a row; a background failure appears as the status line, not a dialog; iPad multi-delete deletes the captured selection).

- [ ] **Step 1: Write the documents.**
- [ ] **Step 2: Gate** `./scripts/verify.sh` green.
- [ ] **Step 3: Commit** `docs(presentation): record the coordinator decision and remove the debug-hook note`.
