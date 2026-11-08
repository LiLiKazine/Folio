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
- **Closed**: the moment SwiftUI writes the presentation flag back to false,
  which per Apple's documentation happens only when a dialog that was shown
  is finished or cancelled.

## Goals

- One Presentation on screen at a time, by construction.
- Nothing requested is lost: every request is queued and shown in order
  once the screen is free.
- A dialog is never requested while another is on screen, so the undefined
  "second presentation" case cannot occur for anything Folio presents.
- No timers, no settle delays, no guard lists.
- Behaviour visible to the user is unchanged: same dialogs, same copy,
  same actions, on iPhone, iPad, and Mac.
- The logic that decides what shows next is a pure value type with unit
  tests; the view only renders the coordinator's current Presentation.

## Non-goals

- Dialogs the system presents on its own (permission prompts). Those stay
  outside our control; a queued Presentation waits and shows at the next
  state change, as today.
- Changing the Notice queue semantics (ordering, exact-repeat collapse):
  the Notice queue in `LibraryModel` stays; the coordinator consumes it.
- Multi-window Mac behaviour (each window keeps its own coordinator; a
  Notice still appears in every window, as today).

## Anti-goals

- Any boolean presentation flag that outlives its dialog.
- Any delay chosen empirically.
- A `catch` or guard that silently drops a request.

## Design

### The pure part: `PresentationQueue`

A value type with no SwiftUI dependency:

- `enum Presentation: Equatable, Identifiable` with the five cases above
  (Rename and Delete carry the `Book`; the Notice case carries the Notice).
- `struct PresentationQueue`: `private(set) var current: Presentation?`,
  `private(set) var pending: [Presentation]`.
  - `mutating func enqueue(_ p: Presentation)`: appends; if `current` is
    nil, promotes it immediately and returns `true` (meaning "present now").
    Consecutive identical Notices collapse (same rule as today). An Import
    picker request while one is already current or pending is ignored (one
    picker at a time).
  - `mutating func closed(_ id: Presentation.ID) -> Presentation?`: called
    when the current Presentation reports it closed; clears `current` and
    returns the next one, promoting it to `current`, or nil. A stale id
    (not the current one) is ignored and returns nil.
  - `var isBusy: Bool { current != nil }`.

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
- Notices: the view observes `model.presentedNotice`; whenever it changes
  to a Notice not yet enqueued, the view enqueues it. The Notice's `OK`
  calls `model.dismissNotice(id)` as today; the coordinator learns it
  closed through SwiftUI's write-back, then shows the next Presentation,
  which may be the next Notice.
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
  now; enqueue when busy queues in order; `closed` promotes the next;
  stale `closed` is ignored; identical consecutive Notices collapse; a
  second picker request is ignored while one is current or pending; mixed
  sequence (Notice, picker, Rename, Notice) shows in order.
- `LibraryModelTests`: unchanged (the Notice queue is unchanged).
- Manual verification on Mac and on a single-display iPhone simulator with
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
