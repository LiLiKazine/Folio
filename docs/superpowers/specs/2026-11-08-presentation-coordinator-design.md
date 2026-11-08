# Presentation Coordinator — Design

Date: 2026-11-08
Status: ready for approval
Glossary: `CONTEXT.md` is authoritative. Capitalised terms are glossary terms.

## Intent

The Library screen shows five kinds of dialog: a Notice, the file picker, the
Rename box, the Delete Book confirmation, and the iPad multi-delete
confirmation. Today each has its own true/false flag, and SwiftUI is asked to
show whichever flags are true. SwiftUI shows one dialog at a time; when a
second is requested while one is up, the documentation guarantees nothing, and
on some OS versions the second never appears and its flag is left true
forever. The current code papers over this with a guard list and a 150 ms
delay. That is a workaround.

This slice replaces the five flags with one source of truth: a single
presentation coordinator that owns a queue of things to show, shows exactly
one, and shows the next only after the current one has reported that it
closed. The question "is anything else on screen" is then answered by
construction for everything the app presents, not by a list someone must keep
current.

## Definitions (mechanisms, in plain language)

- **Presentation**: one dialog the Library screen can show. Exactly one of:
  a Notice, the Import picker, Rename for a given Book, Delete confirmation
  for a given Book, Delete confirmation for the selected Books.
- **Coordinator**: the one object that holds the queue of pending
  Presentations and the single Presentation currently on screen.
- **Closing**: the moment SwiftUI writes the presentation flag back to
  false, which per Apple's documentation happens when a dialog that was
  shown is finished or cancelled. The dialog is still animating away.
- **Closed**: the moment the dialog is gone from the screen. For a Notice or
  a confirmation this is the documented `onDisappear` of the dialog's own
  content (its message text), which SwiftUI calls when that content leaves
  the view hierarchy. For the file picker, which has no content view of
  ours, it is the write-back to false followed by one main-actor turn.

## Goals

- One Presentation on screen at a time, by construction.
- Nothing requested is lost: every request is queued and shown in order
  once the screen is free.
- A dialog is never requested while another is on screen, so the undefined
  "second presentation" case cannot occur for anything Folio presents.
- No timers and no empirically chosen delays. The only wait is for the
  documented `onDisappear` of the closing dialog (or one main-actor turn
  after the picker's write-back, since the picker has no content of ours).
  No guard lists.
- Behaviour visible to the user is unchanged: same dialogs, same copy,
  same actions. The coordinator lives in the shared Library screen, so it
  applies identically on iPhone, iPad, and Mac; only what feeds the queue
  differs per platform (⌘I on Mac, Select-mode delete on iPad).
- The logic that decides what shows next is a pure value type with unit
  tests; the view only renders the coordinator's current Presentation.

## Non-goals

- Dialogs the system presents on its own (permission prompts). Those stay
  outside our control. If one causes SwiftUI to refuse a Presentation the
  coordinator asked for, there is no documented signal of the refusal and
  no recovery short of the next state change; this is the residual risk,
  stated plainly, and it is no worse than today.
- Changing the Notice queue semantics (ordering, exact-repeat collapse):
  the Notice queue in `LibraryModel` stays; the coordinator consumes it.
- Multi-window behaviour on Mac and iPad (each window keeps its own
  coordinator; a Notice still appears in every window, as today).

## Anti-goals

- Any boolean presentation flag that outlives its dialog.
- Any delay chosen empirically.
- A `catch` or guard that silently drops a request.

## Design

### The pure part: `PresentationQueue`

A value type with no SwiftUI dependency:

- `enum Presentation: Equatable, Identifiable` with the five cases above
  (Rename and Delete carry the `Book`; the Notice case carries the Notice).
- `struct PresentationQueue` with three states for the screen: idle,
  showing `current`, and closing (the current dialog is animating away and
  nothing may be requested yet). Fields: `private(set) var current:
  Presentation?`, `private(set) var isClosing: Bool`, `private(set) var
  pending: [Presentation]`.
  - `mutating func enqueue(_ p: Presentation) -> Bool`: appends; if idle,
    promotes it immediately and returns `true` ("present now"). A picker
    request while one is already current or pending is ignored (one picker
    at a time). No collapsing of Notices here: the model's Notice queue
    already collapses exact repeats, and the coordinator only ever holds
    the model's single current Notice (see Notices below).
  - `mutating func closing(_ id: Presentation.ID)`: SwiftUI wrote the flag
    back to false; marks the screen closing. A stale id is ignored.
  - `mutating func closed(_ id: Presentation.ID) -> Presentation?`: the
    dialog is gone; clears `current` and `isClosing`, promotes and returns
    the next pending Presentation, or nil. A stale id is ignored.
  - `var isIdle: Bool { current == nil && !isClosing }`.
  Because promotion happens only in `closed`, the flag of any one modifier
  is observably false for the whole dismissal, so the same kind of dialog
  can follow itself (Notice after Notice).

### The SwiftUI part

- `LibraryView` holds `@State private var queue = PresentationQueue()` and
  renders exactly one modifier per Presentation kind, each driven by a
  binding derived from `queue.current`: true when `current` is that case,
  and whose setter on `false` calls `queue.closed(current.id)`. Each
  dialog's action buttons perform their work and then rely on SwiftUI's
  own write-back of false (per the documentation) to call `closed`.
- Every place that today sets a flag (`isImporting = true`,
  `bookToRename = book`, `bookToDelete = book`, Select-mode delete, the
  Notice hand-over) instead calls `queue.enqueue(...)`.
- Notices: the coordinator holds at most one Notice, the model's current
  one, identified by its id. Whenever the queue becomes idle, or
  `model.presentedNotice` changes, the view enqueues `.notice(id)` if that
  id is not already current or pending. The Notice's `OK` calls
  `model.dismissNotice(id)` as today. A Notice that leaves the screen
  without OK (the system closed it) is still the model's current Notice,
  so it is re-enqueued when the queue next goes idle and shown again; a
  Notice another window already dismissed is no longer the model's current
  Notice and is never shown.
- Stale subjects: when a pending Presentation reaches the front, the view
  checks its subject still exists. Rename or Delete for a Book no longer in
  `items`, a delete-selection whose captured ids are all gone, or a Notice
  the model no longer presents is skipped with a log line labelled
  `// Log-only:` ("the thing the dialog would act on is already gone, so
  there is nothing to show or to fail"). This is the one justified skip.
- Capture at request time: Rename and Delete carry the `Book`; the
  delete-selection carries the `Set<BookID>` selected when the user tapped
  Delete, and uses that set for both its title count and the deletion, so
  later selection changes cannot alter what it does. Select mode behaves as
  today otherwise.
- Because a Presentation is only ever requested from the coordinator when
  `current` was nil, SwiftUI is never asked to present over an existing
  presentation. The gate, the settle delay, `isSettling`,
  `ImportRequestGate`, `isPresentingOtherDialog`, and the five flags are
  deleted.

### Cross-cutting

- ⌘I on Mac: `LibraryCommands` keeps the same focused-value mechanism, but
  the value it toggles is a request that the view turns into
  `queue.enqueue(.importPicker)`.
- Drag-and-drop and the empty-state button request the picker the same
  way (drop still imports directly without a picker).
- The DEBUG hook `FOLIO_DEBUG_NOTICES` stays as the manual-check tool and
  gains `=sequence`: queues Notice, picker request, Notice in that order 1 s
  after launch, so the hand check can confirm the three appear one after
  another with no user action other than closing each.

## Tests

- `PresentationQueueTests` (app target, pure): enqueue when idle presents
  now; enqueue when showing or closing queues in order; `closing` blocks
  promotion; `closed` promotes the next; stale `closing`/`closed` ignored;
  a second picker request is ignored while one is current or pending; a
  Notice id already current or pending is not enqueued twice; mixed
  sequence (Notice, picker, Rename, Notice) shows in order.
- `LibraryModelTests`: unchanged (the Notice queue is unchanged).
- Manual verification on Mac, on a single-display iPhone simulator, and on
  an iPad simulator (including the Select-mode delete confirmation) with
  `FOLIO_DEBUG_NOTICES=sequence`, plus the owner's own sequence (⌘I while
  a Notice is showing, close it, picker appears).

## What is removed

`ImportRequestGate` and its tests, `isSettling`, `isPresentingOtherDialog`,
`shownNotice`, `isImporting`, `bookToRename`, `bookToDelete`,
`isConfirmingDeleteSelection` as independent flags, and the 150 ms delays.
DECISIONS.md records why the earlier approach was a workaround and what
replaced it, in plain language.

## Left to the builder

- Whether `Presentation` lives in its own file next to `Notice.swift`.
- How the Rename text field state is seeded when the Rename Presentation
  becomes current.
- The exact derived-binding helper shape.
