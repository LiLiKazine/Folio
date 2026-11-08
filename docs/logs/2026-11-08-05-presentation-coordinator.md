# 2026-11-08-05: The Library screen presents every dialog from one queue

**Status:** Implemented (owner's manual checks pending)

## Context

The Library screen showed its dialogs (the file picker, Rename, Delete, the
iPad's multi-delete, and Notices) from separate flags. SwiftUI refuses a
second dialog from the same screen without saying so, so the screen grew a
workaround layer: a 150 ms settle delay, an import request gate, and checks
for "is another dialog up". A Notice could still be lost or block the picker.
Background failures were also shown as dialogs, which the Human Interface
Guidelines advise against. Design:
`docs/superpowers/specs/2026-11-08-presentation-coordinator-design.md`.

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

The design forbids delays, polling, and guard lists. A single optional
current Presentation makes two dialogs on screen at once impossible, so no
check is needed at the request sites.

## What Changed

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
