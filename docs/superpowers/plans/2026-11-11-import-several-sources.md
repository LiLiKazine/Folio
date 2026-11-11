# Importing Several Sources at Once Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The reader ticks several zips in the file picker, or drops several folders and zips on the Mac's Library window, and each becomes its own Import and Book.

**Architecture:** Nothing changes in FolioCore: `Library.createImport(from:)` already queues one Import per call and runs them in creation order. `LibraryModel` gains `importSources(_:)`, which creates the Imports one after another in the order delivered and holds each Source's security scope while doing so. `LibraryWindow` opens the picker with several allowed and hands every delivered URL to the model; the Mac drop target accepts a drop made only of folders and zips.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI (`fileImporter`, `dropDestination`), Swift Testing. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-11-import-several-sources-design.md` (glossary `CONTEXT.md`; builds on `docs/superpowers/specs/2026-11-08-library-and-import-design.md` and `2026-11-08-visible-failures-design.md`). Read it before any task, including "What the spike found".

## Global Constraints

- `CONTEXT.md` terms exactly: Source, Import, Book, Notice, Library. Never the `_Avoid_` words (for Import: "add", "open", "load", "upload", "task", "job"; for Source: "original", "file", "archive"). This covers code, tests, copy and commits. "Batch" is not a glossary term; do not introduce it in code or copy.
- No change in `app/FolioCore`. No new on-screen words; no change to `Localizable.xcstrings`.
- One Import per Source, created one after another in the order the picker or the drop delivers them, each awaited before the next. Never one task per Source.
- A Source that cannot be referenced queues its own Notice, and the remaining Sources are still handed to the Library.
- When the Library cannot save an Import, every Source is still tried and exactly one "Couldn't Import" Notice results (the existing rule that drops a repeated Notice). This is the owner's ruling.
- Folio does not enforce "zips only" in the picker; it imports whatever the picker delivers. The Mac drop accepts folders and zips in any mix and refuses the whole drop if it is empty or holds anything else.
- If anything observed contradicts the spec's "What the spike found", stop and report to the owner; do not choose a fallback.
- Designs rest on Apple's documentation, quoted in the log; where it is silent, say what was observed. No timers, delays or guards around undocumented timing.
- No keystrokes or clicks are sent to the owner's Mac. iPhone and iPad checks run on a simulator; Mac checks go on the owner's check list as not checked.
- Swift 6 strict concurrency, warnings as errors; Swift Testing only; OSLog only (`AppLog.library`); SwiftUI only.
- Commands: `./scripts/test.sh macos` to iterate; `./scripts/test.sh` for every platform; `./scripts/verify.sh` as the gate; `./scripts/format.sh --check` clean.
- Every task ends with every target compiling and its tests green. Commit after each task with the `structured-commit` skill, authored as LiLi, ending with `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01LmeQ4kF6jaBLLT9tw3CStM`. Work on branch `feature/import-several-sources`, cut from `main` after the spec and this plan are committed there. Never run `git reflog expire`, `git gc --prune` or any other command that discards history; to correct a commit, amend it or add another.

## Review Focus

1. Several Sources where one in the middle cannot be referenced: the others still become Imports, in the order delivered, and exactly one Notice names the one that failed. Pinned in Task 1.
2. Several Sources while the Library cannot save: no Import items, every Source tried, exactly one "Couldn't Import" Notice. Pinned in Task 1.
3. A drop of zips with one item that is neither a folder nor a zip: the whole drop is refused and nothing is imported. Pinned in Task 2.
4. An empty delivery (the picker confirmed with nothing, or an empty drop): nothing happens, no Notice. Pinned in Tasks 1 and 2.
5. Exactly one Source, picked or dropped: the same Import, Book and Notices as before this change. Pinned by the existing single-Source tests, which Task 1 moves to the new function without changing what they assert.

---

## File Structure

- Modify `app/Folio/Library/LibraryModel.swift`: `importSources(_:)` replaces `importSource(_:)`.
- Modify `app/Folio/Library/LibraryWindow.swift`: the picker allows several; every delivered URL goes to the model.
- Modify `app/Folio/Library/LibraryDropTarget.swift`: `sources(in:)` replaces `source(in:)`; `onImport` takes `[URL]`.
- Tests: modify `app/FolioTests/LibraryModelTests.swift`, `app/FolioTests/LibraryDropTargetTests.swift`.
- Docs: `DECISIONS.md`, `docs/logs/2026-11-11-NN-import-several-sources.md` (NN is the next free number for the day).

---

### Task 1: The model imports several Sources; the picker allows several

**Files:** Modify `app/Folio/Library/LibraryModel.swift`, `app/Folio/Library/LibraryWindow.swift`; Test `app/FolioTests/LibraryModelTests.swift`.

**Interfaces (produces):**
```swift
// LibraryModel — replaces importSource(_:)
/// Creates one Import per Source, in the order given, each awaited before the next.
/// Each Source's security scope is held while its Import is created. A Source that
/// fails queues its Notice and the rest are still handed to the Library.
func importSources(_ urls: [URL]) async
```
Task 2 consumes it through `LibraryWindow.importSources(_ urls: [URL])` (private), which this task also produces in place of the window's `importSource(_:)`.

- [ ] **Step 1: Read Apple's documentation** for `fileImporter(isPresented:allowedContentTypes:allowsMultipleSelection:onCompletion:)` and `URL.startAccessingSecurityScopedResource()`. Note the sentences about choosing several items and about each returned URL's security scope, for the log.

- [ ] **Step 2: Write the failing tests** in `LibraryModelTests.swift`, beside `importFlow`. Sources are made with the existing `makeImageSource(named:pageCount:in:)`; an unreferenceable Source is a URL under `fixture.root` listed in `InMemorySourceAccess.unbookmarkable`, as `importUnavailableNotice` does.

```swift
@Test("several Sources become Imports in the order given, and each a Book")
func importSeveral() async throws {
    // imports: InMemoryImportRepository kept by the test; three Sources "C", "A", "B"
    await model.importSources([c, a, b])
    try await waitUntil("three Books") { self.titles(of: model.items).count == 3 }
    // the repository returns Imports createdAt ascending
    #expect(try await imports.imports(status: .completed).map(\.title) == ["C", "A", "B"])
    #expect(model.notices.isEmpty)
}

@Test("a Source that cannot be referenced gets its Notice and the rest are still imported")
func importSeveralOneUnavailable() async throws {
    // "First" and "Last" are real Sources; "Vol 3" is unbookmarkable
    await model.importSources([first, vol3, last])
    #expect(copy(of: model.notices) == [[
        "Couldn't Import “Vol 3”",
        "Folio couldn't open the folder or zip. Pick it again from the file picker.",
    ]])
    try await waitUntil("two Books") { self.titles(of: model.items).count == 2 }
    #expect(try await imports.imports(status: .completed).map(\.title) == ["First", "Last"])
}

@Test("two Sources that cannot be referenced get one Notice each, in order")
func importSeveralTwoUnavailable() async throws {
    // "Vol 3" and "Vol 4", both unbookmarkable
    await model.importSources([vol3, vol4])
    #expect(model.notices.map(\.title) == ["Couldn't Import “Vol 3”", "Couldn't Import “Vol 4”"])
}

@Test("several Sources while the Library cannot save an Import give one Couldn't Import Notice and no Imports")
func importSeveralCannotSave() async throws {
    // imports: FailingImportRepository failing [.add]; three real Sources
    await model.importSources([a, b, c])
    #expect(copy(of: model.notices) == [[
        "Couldn't Import",
        "Folio couldn't save the change. Try again; if it keeps happening, relaunch Folio.",
    ]])
    #expect(model.items.isEmpty)
}

@Test("no Sources does nothing")
func importNone() async throws {
    await model.importSources([])
    #expect(model.notices.isEmpty)
    #expect(model.items.isEmpty)
}
```
Change every existing `model.importSource(x)` call in this file to `model.importSources([x])`. Do not change what those tests assert.

- [ ] **Step 3: Run them and see them fail to compile**

Run: `./scripts/test.sh macos`
Expected: build error, `importSources` not found.

- [ ] **Step 4: Implement `LibraryModel.importSources(_:)`** in place of `importSource(_:)`: a `for` over the URLs; for each, `startAccessingSecurityScopedResource()`, then the existing `perform(.import) { try await library.createImport(from: url) }`, then `stopAccessingSecurityScopedResource()` if access was started.

- [ ] **Step 5: Update `LibraryWindow`**: `allowsMultipleSelection: true`; `importPicked` passes all the URLs on success and does nothing for an empty array; the private `importSource(_ url:)` becomes `importSources(_ urls: [URL])`, one `Task` that awaits `model.importSources(urls)`, with the security-scope calls removed from the window. Keep the Mac drop compiling for now by passing `{ importSources([$0]) }` to `libraryDropTarget` (Task 2 changes it).

- [ ] **Step 6: Run the tests on every platform**

Run: `./scripts/test.sh && ./scripts/format.sh --check`
Expected: PASS.

- [ ] **Step 7: Check on simulators**, with the `sim-use` skill and `SIMULATOR=<udid of a single-display iPhone> ./scripts/run.sh ios`. Put three zips and one zip with no images in the simulator's Files app ("On My iPhone").
  - Tick three zips and press Open: three Import cards, then three Books.
  - Go into a folder and press Open: one card, one Book.
  - Tick two good zips and the one with no images: two Books, one Failed card, one Notice naming it.
  - Open the picker and cancel: nothing happens.
  - Repeat the first two on an iPad simulator.
  Record the device, the iOS version and what was seen. If anything contradicts the spec's "What the spike found", stop and report.

- [ ] **Step 8: Commit**

Commit: `feat(import): the file picker takes several Sources and each becomes its own Import`

---

### Task 2: The Mac drop target takes several Sources

**Files:** Modify `app/Folio/Library/LibraryDropTarget.swift`, `app/Folio/Library/LibraryWindow.swift`; Test `app/FolioTests/LibraryDropTargetTests.swift`.

**Interfaces:**
- Consumes: `LibraryWindow.importSources(_ urls: [URL])` (Task 1).
- Produces:
```swift
// LibraryDropTarget — replaces source(in:)
/// The Sources in a drop, in the drop's order, or nil when the drop is empty or
/// holds anything that is not a folder or zip.
nonisolated static func sources(in urls: [URL]) -> [URL]?
let onImport: ([URL]) -> Void
// View
func libraryDropTarget(onImport: @escaping ([URL]) -> Void) -> some View
```

- [ ] **Step 1: Rewrite the tests** in `LibraryDropTargetTests.swift` for `sources(in:)`, using the file's existing `folder`, `zip` and `notASource` values and its two real-file tests:

```swift
#expect(LibraryDropTarget.sources(in: [folder]) == [folder])                 // "one folder is a Source"
#expect(LibraryDropTarget.sources(in: [zip]) == [zip])                       // "one zip is a Source, whatever the extension's case"
#expect(LibraryDropTarget.sources(in: [notASource]) == nil)                  // "a URL that is neither a folder nor a zip is rejected"
#expect(LibraryDropTarget.sources(in: [zip, folder, zip]) == [zip, folder, zip]) // "several folders and zips are Sources, in the drop's order"
#expect(LibraryDropTarget.sources(in: [zip, notASource, folder]) == nil)     // "a drop holding anything else is rejected whole"
#expect(LibraryDropTarget.sources(in: []) == nil)                            // "an empty drop is rejected"
// "a real folder without a trailing slash is a Source": sources(in: [url]) == [url]
// "a real file with no extension is rejected": sources(in: [url]) == nil
```
The test "several URLs are rejected, even if each would be a Source" is deleted; the fourth line replaces it.

- [ ] **Step 2: Run them and see them fail to compile**

Run: `./scripts/test.sh macos`
Expected: build error, `sources(in:)` not found.

- [ ] **Step 3: Implement** `sources(in:)` (nil for an empty array; nil unless every URL is a folder or ends in `zip`, case ignored; otherwise the array as given), `onImport: ([URL]) -> Void`, and the drop handler calling `onImport(sources)`. Update the type's comment, `source`'s replacement comment and `libraryDropTarget`'s comment to say several. In `LibraryWindow`, pass `importSources` directly.

- [ ] **Step 4: Run the tests on every platform**

Run: `./scripts/test.sh && ./scripts/format.sh --check`
Expected: PASS.

- [ ] **Step 5: Commit**

Commit: `feat(import): several folders and zips dropped on the Mac's Library window are each imported`

---

### Task 3: Decisions, the log and the owner's check list

**Files:** Modify `DECISIONS.md`; Create `docs/logs/2026-11-11-NN-import-several-sources.md`.

- [ ] **Step 1: `DECISIONS.md`**, in plain language, each entry stating what the user experiences: several Sources can be ticked or dropped at once and each becomes its own Import; in the picker on iPhone that means several zips, with a folder picked one at a time as before, because the system picker does not tick folders; the order within one visit is whatever the picker delivers; a picked folder is still one Book and its zips are not looked into; a drop holding anything else is refused whole, and why; each failure keeps its own Notice, except that a Library that cannot save shows one Notice for all of them, and why; picking one zip on iPhone takes one more tap. Correct the earlier entry that says the Mac drop takes one Source.

- [ ] **Step 2: The log**, in the structure the Library Order implementation log uses: summary, context (the owner's request, the spike and its findings, the rulings), options considered and rejected (the folder-of-zips case; mixing; naming the Source in the save-failure Notice; stopping at the first save failure; enforcing zips only), what changed per task, Apple documentation relied on (quoted), what the documentation does not say (observed), simulator checks, tests, what was discovered, not checked, commits.

- [ ] **Step 3: The owner's check list** in that log, covering at least: ticking several zips on a real iPhone from the Files app; one folder picked as before; one zip that fails among several; the Mac's picker and File → Import… with several, and whether it lets folders and zips be chosen together (each becomes a Book if it does); dropping several folders and zips on the Mac; a drop with a PDF among zips springs back; exactly one Source picked or dropped still works on each platform. Mark each as seen on a simulator or not checked.

- [ ] **Step 4: The gate**

Run: `./scripts/verify.sh`
Expected: "green — all enabled platforms format, build, test, and launch".

- [ ] **Step 5: Commit**

Commit: `docs(import): record the decisions for importing several Sources and the owner's check list`
