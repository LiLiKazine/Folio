# Visible Failures Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every action the user takes in the Library either visibly succeeds or visibly fails, on iPhone, iPad, and Mac, with a forced-failure test per operation.

**Architecture:** `LibraryError` becomes the only error the `Library` actor's public operations throw, every case presentable. Failures inside the scheduler and launch recovery that have no caller emit a new `LibraryEvent.libraryStorageFailed(operation)`. `LibraryModel` turns every `LibraryError` and every `libraryStorageFailed` event into a queued `Notice`, and the existing Import failure alert becomes one kind of Notice. `LibraryView` presents Notices one at a time as a system alert. The codebase rule lands in `CLAUDE.md`.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, Swift Testing, OSLog. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-08-visible-failures-design.md` (glossary: `CONTEXT.md`, now with Notice and LibraryStorageFailed)

## Global Constraints

- Use `CONTEXT.md` terms exactly in identifiers, tests, commits, and UI copy; never the `_Avoid_` words (no "toast", "alert" as a noun in identifiers or copy for a Notice, "error message", "banner").
- Swift 6 language mode, strict concurrency complete, warnings are errors. Swift Testing only. OSLog only, no `print`. All user-facing strings localizable; after building, sync the catalog with the `xcstringstool sync` invocation recorded in `docs/logs/2026-11-08-03-library-and-import-implementation.md`.
- A `catch` that only logs is a defect unless a comment at the site says why nothing the user sees depends on it.
- Operation names (exact): `Import`, `Cancel Import`, `Retry Import`, `Remove Import`, `Rename`, `Open`, `Delete Book`, `Update the Library`, `Open the Library`.
- Notice copy exactly as the spec's table, including `Couldn't <Operation>` titles and the `Couldn't Import “<Source>”` form.
- Notices queue in order; a second failure never overwrites the first.
- Commands: `swift test --package-path app/FolioCore -Xswiftc -warnings-as-errors` for the package; `./scripts/test.sh` for the whole suite (both platforms); `./scripts/verify.sh` as the gate. Commit after every task with the `structured-commit` format and the attribution lines `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01LmeQ4kF6jaBLLT9tw3CStM`.

## Review Focus

1. A failure while a Notice is already on screen must not be lost: the second Notice appears after the first is dismissed. Test in Task 3.
2. Cancelling an Import the user asked to cancel must still produce no Notice (spec rule from the previous slice). Test in Task 3.
3. A repository that throws on *read* during `items()` must yield `Update the Library`, not an empty Library with no message. Test in Task 3.
4. A `LibraryError` raised on the Mac from the file picker path must present even though the view's import call runs inside an unstructured `Task`. Test in Task 3 (model level) and gate in Task 4.
5. The scheduler must keep running after emitting `libraryStorageFailed` for a failed status write; the next Queued Import still runs. Test in Task 2.

---

## File Structure

FolioCore (`app/FolioCore/Sources/FolioCore/`):
- `Library/LibraryError.swift` (new): `LibraryError` with presentable cases and `LibraryOperation`.
- `Library/Library.swift` (modify): wrap every escaping error; emit `libraryStorageFailed`; justify remaining log-only catches.
- `Domain/LibraryEvent.swift` (modify): add `libraryStorageFailed(LibraryOperation)`.
- `Domain/FailingRepositories.swift` (new): public failing repository doubles.
- Tests: `LibraryErrorTests.swift` (new), `LibraryTests.swift` (modify).

App (`app/Folio/`):
- `Library/Notice.swift` (new): `Notice` value and the copy table.
- `Library/LibraryModel.swift` (modify): `notices` queue, `presentedNotice`, mapping from errors and events; `FailureAlert` removed.
- `Library/LibraryView.swift` (modify): one `.alert` driven by `presentedNotice`.
- `Logging.swift` unchanged.
- Tests: `app/FolioTests/NoticeTests.swift` (new), `LibraryModelTests.swift` (modify).

Docs: `CLAUDE.md` (rule), `DECISIONS.md` (entry), `docs/logs/2026-11-08-04-visible-failures.md` (new).

---

### Task 1: Presentable Library errors

**Files:**
- Create: `app/FolioCore/Sources/FolioCore/Library/LibraryError.swift`
- Modify: `app/FolioCore/Sources/FolioCore/Library/Library.swift` (remove the existing `LibraryError` declaration at its top; wrap thrown errors)
- Create: `app/FolioCore/Sources/FolioCore/Domain/FailingRepositories.swift` (public test doubles, like the in-memory repositories, so the app tests can use them too)
- Test: `app/FolioCore/Tests/FolioCoreTests/LibraryErrorTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum LibraryOperation: String, Sendable, Equatable, CaseIterable {
      case `import` = "Import", cancelImport = "Cancel Import", retryImport = "Retry Import",
           removeImport = "Remove Import", rename = "Rename", open = "Open",
           deleteBook = "Delete Book", updateLibrary = "Update the Library",
           openLibrary = "Open the Library"
  }
  public enum LibraryError: Error, Equatable, Sendable {
      case emptyTitle
      case notFound(LibraryOperation)
      case invalidStatus(LibraryOperation)
      case sourceUnavailable(sourceName: String)
      case sourceNotDownloaded(sourceName: String)
      case storage(LibraryOperation)
      public var operation: LibraryOperation   // emptyTitle → .rename; sourceUnavailable/sourceNotDownloaded → .import
  }
  ```
  Every `public func` on `Library` is documented as throwing only `LibraryError`. Internally, a private helper `func storageGuard<T>(_ op: LibraryOperation, _ body: () async throws -> T) async throws(LibraryError) -> T` rethrows `LibraryError` unchanged and wraps anything else as `.storage(op)` after logging it at `.error`.
  `createImport` maps `SourceAccessError.unavailable` → `.sourceUnavailable(sourceName:)`, `.notDownloaded` → `.sourceNotDownloaded(sourceName:)`.
  Test doubles (public, in the main target): `public actor FailingBookRepository: BookRepository` and `public actor FailingImportRepository: ImportRepository`, each wrapping an in-memory repository, with `public func fail(_ calls: Set<RepositoryCall>)` and `public func succeed()`; `public enum RepositoryCall: Sendable { case allBooks, book, add, update, remove, imports, importRecord }`; a call in the failing set throws `public struct RepositoryFailure: Error {}`.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite("Library errors are presentable")
struct LibraryErrorTests {
    @Test("rename with an empty Title throws emptyTitle") func emptyTitle() async throws
    @Test("rename of an unknown Book throws notFound(.rename)") func renameNotFound() async throws
    @Test("retry of a Queued Import throws invalidStatus(.retryImport)") func retryInvalid() async throws
    @Test("createImport with an unavailable Source throws sourceUnavailable with the Source name") func createUnavailable() async throws {
        /* InMemorySourceAccess with the path in `unavailable`; folder named "Chapter 01" → .sourceUnavailable(sourceName: "Chapter 01") */
    }
    @Test("a repository write failure surfaces as storage(operation)", arguments: [
        (FailingRepositories.Call.add, LibraryOperation.import),      // createImport → imports.add
        (.update, .rename),                                           // rename → books.update
        (.update, .open),                                             // open → books.update
        (.remove, .deleteBook),                                       // removeBook → books.remove
    ]) func storage(call: FailingRepositories.Call, op: LibraryOperation) async throws
    @Test("items() with a failing read throws storage(.updateLibrary)") func itemsRead() async throws
    @Test("every LibraryError has an operation") func operations() { for each case, #expect(error.operation is a LibraryOperation) }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path app/FolioCore -Xswiftc -warnings-as-errors --filter LibraryErrorTests`
Expected: compile failure (`LibraryOperation` not found).

- [ ] **Step 3: Implement `LibraryError.swift`, the failing repositories, and wrap `Library`'s public operations with `storageGuard`.** Replace existing throws of the old `notFound`/`invalidStatus` with the operation-carrying cases. Existing tests in `LibraryTests` that match on `LibraryError.notFound` or `.invalidStatus` are updated to the new cases.

- [ ] **Step 4: Run the whole package suite.** Run: `swift test --package-path app/FolioCore -Xswiftc -warnings-as-errors`. Expected: PASS.

- [ ] **Step 5: Commit**

`feat(library): typed presentable LibraryError with operation`

---

### Task 2: Failures without a caller become events

**Files:**
- Modify: `app/FolioCore/Sources/FolioCore/Domain/LibraryEvent.swift`
- Modify: `app/FolioCore/Sources/FolioCore/Library/Library.swift`
- Test: `app/FolioCore/Tests/FolioCoreTests/LibraryTests.swift`

**Interfaces:**
- Produces: `case libraryStorageFailed(LibraryOperation)` on `LibraryEvent`.
- Emission sites (exact mapping from the spec):
  - `fail()` could not write the Failed status after one retry → `.libraryStorageFailed(.import)`
  - scheduler queue fetch failed → `.libraryStorageFailed(.updateLibrary)`
  - reconciliation could not remove a Book record whose folder is missing → `.libraryStorageFailed(.updateLibrary)`
  - `removeBook` could not delete the folder after removing the record → `.libraryStorageFailed(.deleteBook)`
  - `start()` recovery could not read or re-queue In Progress Imports → `.libraryStorageFailed(.openLibrary)` (and `start()` no longer throws; it returns after emitting)
- Remaining log-only catches (temporary-file cleanup, orphan folder deletion in reconciliation, progress writes) each gain a one-line comment beginning `// Log-only:` saying why nothing the user sees depends on it.

- [ ] **Step 1: Write the failing tests**

```swift
@Test("a Failed status that cannot be saved emits libraryStorageFailed(.import) and the next Import still runs")
func failedStatusUnsaved() async throws { /* FailingImportRepository failing .update only while the first Import's run is failing (toggle via the actor); two Queued Imports; expect .libraryStorageFailed(.import) then .importCompleted for the second */ }
@Test("a failing queue fetch emits libraryStorageFailed(.updateLibrary)") func queueFetch() async throws
@Test("a Book record that cannot be removed in reconciliation emits libraryStorageFailed(.updateLibrary)") func reconcileRecord() async throws
@Test("a Book folder that cannot be deleted emits libraryStorageFailed(.deleteBook) after bookRemoved") func folderUndeletable() async throws
@Test("start() with unreadable In Progress Imports emits libraryStorageFailed(.openLibrary) and does not throw") func startRecoveryRead() async throws
```

- [ ] **Step 2: Run tests to verify they fail.** Run: `swift test --package-path app/FolioCore -Xswiftc -warnings-as-errors --filter LibraryTests`. Expected: compile failure on the new case.

- [ ] **Step 3: Implement the event and the five emission sites; annotate the remaining log-only catches.**

- [ ] **Step 4: Run the package suite.** Expected: PASS, including the existing `recoveryAfterCleanupFailure` and `removeBookLockedFolder`, updated to expect the new events.

- [ ] **Step 5: Commit**

`feat(library): emit LibraryStorageFailed for failures with no caller`

---

### Task 3: Notices in the model

**Files:**
- Create: `app/Folio/Library/Notice.swift`
- Modify: `app/Folio/Library/LibraryModel.swift`
- Create: `app/FolioTests/NoticeTests.swift`
- Modify: `app/FolioTests/LibraryModelTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct Notice: Identifiable, Equatable, Sendable {
      let id: UUID
      let title: String      // "Couldn't Import “Chapter 01”" or "Couldn't Rename"
      let message: String
      init(error: LibraryError)
      init(storageFailed operation: LibraryOperation)
      init(importFailed sourceName: String, reason: ImportFailureReason)   // replaces FailureAlert; reuses the existing reason texts
  }
  ```
  Copy exactly per the spec table; `init(storageFailed:)` message is `Folio couldn't save the change. What you see may be out of date; relaunch Folio to refresh.`; `init(error: .storage(op))` message is `Folio couldn't save the change. Try again; if it keeps happening, relaunch Folio.`; `.openLibrary` message is `Folio couldn't open its Library. Relaunch Folio; if it keeps happening, free up storage.`
  `LibraryModel`: `private(set) var notices: [Notice]`, `var presentedNotice: Notice? { notices.first }`, `func dismissNotice()` removes the first. `FailureAlert` and `failureAlert` are deleted. `perform(_:)` takes a `LibraryOperation` and appends `Notice(error:)` on `LibraryError` (any other error type is a programming error: log and append `Notice(storageFailed: op)`). `start()` no longer throws after Task 2, so the model's `start()` has no catch; the `Open the Library` Notice arrives through the `.libraryStorageFailed(.openLibrary)` event, which the unbounded stream buffers until the model begins consuming. `reload()` failing appends `Notice(error: .storage(.updateLibrary))`. `handle(.importFailed)` appends `Notice(importFailed:reason:)` unless the reason is `.cancelled`; `handle(.libraryStorageFailed(op))` appends `Notice(storageFailed: op)` and reloads.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite("Notice copy") struct NoticeTests {
    @Test("sourceUnavailable names the Source") func sourceUnavailable() { #expect(Notice(error: .sourceUnavailable(sourceName: "Vol 3")).title == "Couldn't Import “Vol 3”") ; message == "Folio couldn't open the folder or zip. Pick it again from the file picker." }
    @Test("emptyTitle") … title "Couldn't Rename", message "A Book needs a Title."
    @Test("notFound uses the operation") … .notFound(.deleteBook) → "Couldn't Delete Book" / "It's no longer in the Library."
    @Test("invalidStatus") … .invalidStatus(.retryImport) → "Couldn't Retry Import" / "That Import has already moved on."
    @Test("storage error") … .storage(.rename) → "Couldn't Rename" / "Folio couldn't save the change. Try again; if it keeps happening, relaunch Folio."
    @Test("storage failed event") … Notice(storageFailed: .updateLibrary) → "Couldn't Update the Library" / "Folio couldn't save the change. What you see may be out of date; relaunch Folio to refresh."
    @Test("open the Library") … Notice(storageFailed: .openLibrary) → "Couldn't Open the Library" / "Folio couldn't open its Library. Relaunch Folio; if it keeps happening, free up storage."
    @Test("import failed keeps the existing reason text") … Notice(importFailed: "x.zip", reason: .noImagesFound).message == "No images found"
}
// LibraryModelTests additions
@Test("an unavailable Source on import yields a Notice naming it") func importUnavailableNotice()
@Test("a failing rename write yields a storage Notice for Rename") func renameStorageNotice()
@Test("two failures queue two Notices in order; dismiss shows the second") func noticesQueue()
@Test("cancel yields no Notice") func cancelNoNotice()   // adapt the existing cancelNoAlert
@Test("items() read failure yields Update the Library") func reloadNotice()
@Test("libraryStorageFailed event yields its Notice") func storageEventNotice()
@Test("start recovery failure yields Open the Library through the event") func startNotice()
```
Build the model over a `Library` with the public `FailingBookRepository`/`FailingImportRepository` from Task 1 and `InMemorySourceAccess`.

- [ ] **Step 2: Run tests to verify they fail.** Run: `./scripts/test.sh macos`. Expected: compile failure.

- [ ] **Step 3: Implement `Notice.swift` and the model changes.** Delete `FailureAlert`.

- [ ] **Step 4: Run tests.** Run: `./scripts/test.sh macos`. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

`feat(library): queue Notices for every failure in LibraryModel`

---

### Task 4: Present Notices in the view

**Files:**
- Modify: `app/Folio/Library/LibraryView.swift`
- Modify: `app/Folio/Localizable.xcstrings` (synced)

**Interfaces:**
- Consumes: `model.presentedNotice`, `model.dismissNotice()`, and the operation-taking `perform` calls (every view action passes its `LibraryOperation`; the import path passes `.import`).
- Produces: one `.alert(presentedNotice.title, isPresented:, presenting:) { Button("OK") }` replacing the old failure alert; the `OK` action calls `model.dismissNotice()`. Title and message come from the `Notice` (already localized at construction in `Notice.swift`, via `String(localized:)` with the operation interpolated).

- [ ] **Step 1: Replace the alert and remove every reference to `failureAlert`.** `grep -rn failureAlert app/` must return nothing.

- [ ] **Step 2: Run the gate.** Run: `./scripts/verify.sh`. Expected: green on iOS and macOS. Sync the string catalog and commit it.

- [ ] **Step 3: Commit**

`feat(library): present Notices as a single queued alert`

---

### Task 5: Rule, decisions, log

**Files:**
- Modify: `CLAUDE.md` (Conventions: add the rule verbatim from the spec's "Rule for the codebase")
- Modify: `DECISIONS.md` (one dated paragraph: why failures are presented, why Notices queue, why log-only catches need a justification comment)
- Create: `docs/logs/2026-11-08-04-visible-failures.md` (structured-commit log format: Context, Options, Decision, Rationale, What Changed, What Was Discovered, with the list of remaining `// Log-only:` sites and the reason for each)

- [ ] **Step 1: Write the three documents.** Run `grep -rn "Log-only:" app/` to list the justified sites for the log.

- [ ] **Step 2: Run the gate once more.** Run: `./scripts/verify.sh`. Expected: green.

- [ ] **Step 3: Commit**

`docs(failures): codebase rule, decision, and implementation log for Visible Failures`
