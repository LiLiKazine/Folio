# 2026-11-08-05: The Library screen presents every dialog from one queue

**Status:** Decided; implemented, owner's manual checks pending

## Context

The Library screen showed its dialogs (the file picker, Rename, Delete, the
iPad's multi-delete, and Notices) from separate flags. SwiftUI refuses a
second dialog from the same screen without saying so, so the screen grew a
workaround layer: a 150 ms settle delay, an import request gate, and checks
for "is another dialog up". A Notice could still be lost or block the picker.
Background failures were also shown as dialogs, which the Human Interface
Guidelines advise against. Design:
`docs/superpowers/specs/2026-11-08-presentation-coordinator-design.md`. The rulings are in `DECISIONS.md` ("Presentation Coordinator"). Terms: a *dialog* is anything the Library screen puts over the grid and waits for the user to answer; a *status line* is a small message at the top of the Library with a Close control; a *write-back of false* is SwiftUI (Apple's screen-building framework) switching a dialog's on/off value off when the dialog closes; a *queue* is a list that is shown one item at a time, in order.

## Options

| Approach | Pros | Cons |
|----------|------|------|
| Keep the flags and tune the delay | No rewrite | A guessed delay; fails silently on slower devices |
| Flags plus guards for every pair of dialogs | No timing | Guard list grows with each dialog; still several flags |
| One `PresentationQueue` read by every dialog modifier (chosen) | One dialog at a time by construction; nothing dropped; pure and tested | Back-to-back dialogs rely on SwiftUI accepting a new presentation right after its write-back of false |

## Decision

`LibraryView` keeps `@State var queue = PresentationQueue()` as its only
presentation state; every request path enqueues, and only SwiftUI's
write-back of false (through `queue.dismissed`) moves to the next dialog.
Background Notices become a status line above the grid.

## Rationale

The design rests on Apple's documentation: a presentation's condition is a
binding, so "SwiftUI can reset the underlying value when the user dismisses
the presentation"; an alert's value is set to false when an action is pressed;
`fileImporter` sets it to false when finished or cancelled; `sheet(item:)`
"dismisses the sheet and replaces it with a new one" when the item changes;
nothing documents a second request while one is showing. The Human Interface
Guidelines say "Avoid using an alert merely to provide information" and
"Avoid showing an alert when your app starts".

The design forbids delays, polling, and guard lists. A single optional
current Presentation makes two dialogs on screen at once impossible, so no
check is needed at the request sites.

## What Changed

Removed, each a workaround for having no single source of truth: the
per-dialog flags; `ImportRequestGate` and its tests; the "is another dialog
up" checks; the 150 ms settle delay; the `FOLIO_DEBUG_NOTICES` debug hook
(and its `CLAUDE.md` paragraph, removed in Task 2); and the test counter of
handled events (`handledEventCount`).

- `app/Folio/Library/LibraryView.swift`: flags and the workaround layer
  removed; one derived binding per dialog kind; the Notice dialog also
  removes its Notice from the model on any dismissal; Rename's text field is
  seeded when a Rename becomes current; the iPad multi-delete uses the
  selection captured when Delete was tapped.
- `app/Folio/Library/LibraryStatusLine.swift` (new): title, message, and a
  Close control, shown with `.safeAreaInset(edge: .top)`.
- `app/Folio/Library/LibraryCommands.swift`: same focused value; setting it
  true enqueues the picker.
- `ImportRequestGate.swift` and its tests deleted.
- `Localizable.xcstrings`: adds `Close`.
- `PresentationQueueTests`: the multi-delete's id is independent of order
  and differs between selections.

## What Was Discovered

- `./scripts/verify.sh`'s macOS launch screenshot (`build/launch-macos.png`)
  captured whatever window was in front (a terminal), not Folio. A capture of
  the Folio window alone (`screencapture -l <window id>`) showed the empty
  state unchanged.
- Two dialogs of the same kind in a row (two Notices) kept the same
  `isPresented` binding true across the hand-over while only its
  `presenting:` value changed, and SwiftUI might never show the second, which
  would leave the queue waiting for a write-back that never comes. Fixed
  (review round 1) without a delay: every dialog modifier now sits on a
  carrier view (`dialogHost`, a `Color.clear` in `.background`) keyed with
  `.id(queue.current?.id)`. SwiftUI documents that a changed `.id` makes a
  new view, so each Presentation is a new presentation request. The grid
  itself is not keyed, so its scroll position survives.
- The same request made twice (⌘I pressed again while the picker waits) was
  queued twice. `PresentationQueue.enqueue` now ignores a request whose id is
  already current or pending; the design's "Nothing is filtered" was changed
  to say so.
- The Rename field is seeded when the Rename is asked for, so it never shows
  the previous Book's Title. Dialogs are modal, so a second Rename cannot be
  asked for while one waits.
- The status line uses a top safe-area inset rather than a `VStack`, so the
  iOS large title still tracks the grid's scroll view.
- A dialog Notice and a status line Notice with identical text never collapse
  into each other (repeats collapse per kind), so a dialog cannot vanish into
  the status line.
- "A view that appears already asking to present will present" is observed,
  not documented, SwiftUI behaviour. The carrier approach relies on it; the
  owner's manual check is the evidence.
- `CLAUDE.md` keeps the single-display-simulator note; the debug-hook
  paragraph is gone.
- Spec change: the Visible Failures design's copy table now has a
  Presentation column (`dialog` or `status line`).

## Gate

- FolioCore: `swift test --package-path app/FolioCore -Xswiftc -warnings-as-errors`: 81 tests in 8 suites passed.
- App tests (`build/last-test.log`, macOS run): 61 tests in 7 suites passed.
- `./scripts/verify.sh` (format, build, test, launch on iOS and macOS): green, exit 0.

## Manual verification still needed

On Mac, iPhone, and iPad:

- Press ⌘I (Mac) or tap plus (iPhone, iPad) while a Notice is showing, then close the Notice: the file picker appears.
- Two Notices in a row appear one after the other, each Close removing exactly one.
- A background failure appears as the status line at the top, not as a dialog.
- iPad: in Select mode, choose several Books, tap Delete, and confirm: exactly the Books chosen when Delete was tapped are deleted.

## Follow-ups

- No test pins the id formats, and the multi-delete ids are not asserted distinct beyond the merged test.
- No test removes a waiting Notice when dialog and status Notices interleave.
- The status line has no VoiceOver announcement (the spoken alert for blind users), and the dialog's title is read from the queue rather than from the presenting value.
- The binding setters read the queue's current dialog when SwiftUI writes back; capturing the id when the binding is made would make a late write-back from a torn-down carrier unable to close the next dialog of the same kind. Also a stale comment on `renameTitle`, and a redundant duplicate check in `requestPresentedNotice`.
- The macOS launch screenshot in `verify.sh` captures whatever window is in front, not Folio.
