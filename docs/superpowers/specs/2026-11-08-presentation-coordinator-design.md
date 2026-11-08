# Presentation Coordinator — Design

Date: 2026-11-08
Status: ready for approval (revised after checking Apple's documentation)
Glossary: `CONTEXT.md` is authoritative. Capitalised terms are glossary terms.

## Intent

The Library screen can show several dialogs: a Notice, the file picker, the
Rename box, the Delete Book confirmation, and the iPad multi-delete
confirmation. Today each has its own true/false flag. SwiftUI shows one
dialog at a time; asking it to show a second while one is up is not covered
by its documentation, and in practice left the picker locked. The current
code works around that with a guard list and a 150 ms delay.

This slice replaces the flags with the pattern Apple's documentation frames
and the SwiftUI community recommends: one source of truth for what is on
screen, so a second dialog can never be requested while one is showing.

## What the documentation says (the basis for this design)

- Apple, Modal presentations: a modifier defines "the condition under which
  SwiftUI presents it … Because you provide a Binding to the condition that
  initiates the presentation, SwiftUI can reset the underlying value when
  the user dismisses the presentation."
- Apple, `alert(_:isPresented:presenting:…)`: "When the user presses or
  taps one of the alert's actions, the system sets this value to false and
  dismisses." Also: "The data should not change after the presentation
  occurs."
- Apple, `fileImporter`: "When the operation is finished, isPresented will
  be set to false … If the user cancels the operation, isPresented will be
  set to false."
- Apple, `sheet(item:)`: "If item changes, the system dismisses the sheet
  and replaces it with a new one."
- Nothing in Apple's documentation describes what happens when a
  presentation is requested while another is showing, or offers a signal
  that a request was refused. Community guidance (Swift Forums,
  swiftui-navigation) is to drive presentation from a single optional
  value so only one can be active.
- Apple, Human Interface Guidelines, Alerts: "Use alerts sparingly."
  "Avoid using an alert merely to provide information." "People don't
  appreciate an interruption from an alert that's informative, but not
  actionable." "Avoid showing an alert when your app starts." For a
  problem detected at startup, "consider alternative ways to let people
  know", such as "a nonintrusive label that describes the problem."

## Definitions (mechanisms, in plain language)

- **Presentation**: one dialog the Library screen can show: a Notice, the
  Import picker, Rename for a given Book, Delete confirmation for a given
  Book, or Delete confirmation for a captured set of selected Books.
- **Dismissed**: SwiftUI has written the presentation's flag back to false,
  which per the documentation happens when the dialog's action ran, the
  picker finished, or the user cancelled.

## Goals

- One Presentation on screen at a time, by construction: a single optional
  value `presentation: Presentation?` is the only thing the view's
  modifiers read, so a second dialog is never requested over a first.
- Requests made while one is showing wait in order and are shown after
  the current one is Dismissed. Nothing is dropped.
- No timers, no delays, no guard lists, no invented completion signals.
  The only transition is SwiftUI's own write-back of false.
- A Notice that has been Dismissed is done. There is no "read" tracking
  and no re-showing.
- Follow the HIG on alerts: Notices about an action the user just took stay
  as dialogs (they answer that action). Notices about background failures
  (LibraryStorageFailed events, the launch failures) stop being dialogs
  and become a nonintrusive status line at the top of the Library grid,
  dismissible, with the same text. This also removes the launch-time alert
  the HIG says to avoid, and removes most situations where dialogs would
  queue behind one another.
- Behaviour on iPhone, iPad, and Mac is the same; only what feeds the queue
  differs per platform (⌘I on Mac, Select-mode delete on iPad).
- The ordering logic is a pure value type with unit tests; the view only
  renders `presentation`.

## Non-goals

- Dialogs the system presents on its own (permission prompts). If one makes
  SwiftUI refuse a request of ours, there is no documented signal and no
  recovery short of the next state change. Stated plainly; it is no worse
  than today and much rarer once background Notices are not dialogs.
- Multi-window behaviour on Mac and iPad (each window keeps its own
  coordinator, as today).
- Changing the Notice copy.

## Anti-goals

- Any boolean presentation flag that outlives its dialog.
- Any delay chosen empirically. If back-to-back dialogs prove unreliable on
  iOS 26 / macOS 26 in the manual check, that is reported as a finding, not
  patched with a delay.
- Skipping or dropping a request silently.

## Design

### Pure part: `PresentationQueue`

- `enum Presentation: Equatable, Identifiable` with the five cases; Rename
  and Delete carry the `Book`; the multi-delete carries the `Set<BookID>`
  captured when the user tapped Delete; the Notice case carries the
  `Notice`.
- `struct PresentationQueue`: `private(set) var current: Presentation?`,
  `private(set) var pending: [Presentation]`.
  - `mutating func enqueue(_ p: Presentation)`: if `current` is nil, it
    becomes current; otherwise it is appended. Nothing is filtered.
  - `mutating func dismissed(_ id: Presentation.ID)`: if `id` is the
    current one, clears it and promotes the first pending item (if any).
    A stale id is ignored.
  - No other operations. No states beyond "current" and "pending".

### SwiftUI part

- `LibraryView` holds `@State private var queue = PresentationQueue()`.
  One modifier per Presentation kind reads `queue.current`: its binding is
  true when `current` is that kind, and its setter on `false` calls
  `queue.dismissed(current.id)`. Dialog buttons perform their action and
  let SwiftUI's documented write-back drive `dismissed`.
- Every place that today sets a flag instead calls `queue.enqueue(...)`.
  `isImporting`, `bookToRename`, `bookToDelete`,
  `isConfirmingDeleteSelection`, `shownNotice`, `isSettling`,
  `ImportRequestGate`, and `isPresentingOtherDialog` are deleted.
- Notices from a user action: the model keeps its Notice queue. The view
  enqueues `.notice(model.presentedNotice)` when it changes and is not
  already current or pending. `OK` calls `model.dismissNotice(id)`; the
  write-back then calls `queue.dismissed`, which may promote the next
  Notice. When a Notice dialog is Dismissed for any reason, the view also
  calls `model.dismissNotice(id)`: Dismissed means done.
- Background Notices (`LibraryStorageFailed` events, launch failures): the
  model marks them `kind: .status`; the view shows the current status
  Notice as a nonintrusive line above the grid with a close control, never
  as a dialog. The Visible Failures spec's copy table gains a
  "Presentation" column with this split; copy is unchanged.
- A Rename or Delete for a Book that no longer exists by the time its
  dialog is confirmed is not special-cased: the Library answers
  `notFound`, which already becomes the "It's no longer in the Library"
  Notice. Nothing is skipped.
- `LibraryCommands` (⌘I) and the drop target request the picker through
  the same `enqueue(.importPicker)` (drop still imports directly).
- The DEBUG hook `FOLIO_DEBUG_NOTICES` and the `handledEventCount` test
  seam in `LibraryModel` are removed: test scaffolding does not belong in
  the app. The manual check is the owner's own sequence on each platform.
  If a later dialog does not appear, that is a finding to report, not
  something to paper over.

## Tests

- `PresentationQueueTests` (pure): enqueue when idle → current; enqueue
  when busy → pending in order; `dismissed` promotes the next; stale
  `dismissed` ignored; mixed sequence (Notice, picker, Rename, Notice) in
  order.
- `LibraryModelTests` that waited on `handledEventCount` observe real state
  (items, notices) instead.
- `LibraryModelTests`: background Notices carry `kind: .status`; action
  Notices carry `kind: .dialog`; everything else unchanged.
- Manual verification by the owner on Mac, iPhone, and iPad: ⌘I (or the
  plus button) while a Notice is showing, close the Notice, the picker
  appears; two Notices in a row appear one after the other.

## Left to the builder

- File placement of `Presentation` and `PresentationQueue`.
- Seeding the Rename text field when the Rename Presentation becomes
  current.
- The derived-binding helper's shape.
- The status line's exact layout within HIG (it must not shift the grid
  jarringly; a small line with text and a close control is enough).
