# 2026-11-08-06: Reading a Book — design rulings

**Status:** Implemented

## Context

Folio could import Books and show them in the Library, but tapping a Cover
only recorded the open; nothing appeared on screen. The owner and the designer
walked through the act of reading with the glossary in hand (the Domain-Driven
Design discipline: settle the words first, then the behaviour). Design:
`docs/superpowers/specs/2026-11-08-reading-design.md`.

Terms used here: the *open Book* is the screen that shows one Page at a time;
*chrome* is the set of controls (Title, page counter, scrubber, Close) that a
tap shows or hides over the Page; a *push* is a screen added on top of the
Library inside the same window so the Library is still underneath; a
*full-screen cover* is a screen SwiftUI (Apple's screen-building framework)
puts in a separate layer above the whole window; *log-only* means a failure
is written to the system log and the user sees nothing.

## Options

| Question | Chosen | Rejected and why |
|----------|--------|------------------|
| After the system kills the app mid-read | Launch lands in the Library; the Book shows its Reading Position | Reopen the Book: more state to keep right, and the owner prefers the Library |
| When is the Reading Position saved | On every Page turn | On close: a kill would lose the position |
| Reopening a Book | Lands on the Reading Position, no prompt | Step back one Page, or ask: the owner wants no questions |
| Past the last Page | Nothing; no "finished" state | A Finished badge: a concept the owner does not want |
| A Page that cannot be decoded | Placeholder in its slot; it still counts | Skip it or show a Notice: nothing for the user to do |
| A Page-turn save fails | Log-only | A Notice: the turn itself visibly succeeded; the Notice would interrupt reading for nothing actionable. Accepted cost: failing saves show up only as an older Page on next open |
| Recording the open fails | Log-only; the Book opens anyway, unless the Library no longer has it | Refuse to open: the Pages are there and readable |
| A Notice arriving while reading | Shown over the open Book, from the root of the window | Hold until close: the owner wants Notices at the root so every present and future screen is beneath them |
| How the open Book is presented | A push on every platform | Full-screen cover: a root-level Notice cannot appear over a cover |
| New glossary terms | One event, ReadingPositionChanged; BookOpened trimmed to the ordering fact | A "Reader" or "Session" noun: the screen is just the open Book; "reader" stays the person |

## Decision

Reading is one pushed screen fed by the existing Book, one new Library
operation (turn Page) that moves the Reading Position and announces
ReadingPositionChanged, and Notices moved to the root of the window.

## Rationale

The owner's rulings are listed in the design under "What the owner decided".
The root-level Notice rule came from the owner as a general principle: in a
tab app the tab bar would show them, in a navigation app the NavigationStack
does. The push-not-cover consequence was identified by the designer and
accepted by the owner in the same exchange.

The designer's own calls after the builder check: an open Book belongs to its
window on Mac; opening a never-read Book sets its Reading Position to the first
Page at once (it follows from the glossary definition); "Open" on Mac is
double-click or Return, with no File menu item in this slice.

## What Changed

- Implemented in six commits (table below): `Library.turnPage` and the
  ReadingPositionChanged event in FolioCore; `LibraryModel` open-regardless,
  log-only `turnPage`, `pageURL`, `removeBooks`; `LibraryWindow` owning the
  navigation path and every dialog; Page decoding and cache; the reading
  screen; the rulings in `DECISIONS.md` and `CLAUDE.md`.

- `CONTEXT.md`: BookOpened trimmed; ReadingPositionChanged added.
- `docs/superpowers/specs/2026-11-08-reading-design.md`: new.

## What Was Discovered

- The Book value, its stored form, and the Library card already carried a
  Reading Position and showed "Page n of N"; only the screen and the
  operation that moves the position were missing.
- The design was reviewed once by a fresh builder, who raised four
  questions: Notices while reading, multi-window on Mac, the first-open
  position, and what "Open" means on Mac. All four are now settled in the
  design.
- This branch was cut from `feature/presentation-coordinator` while that
  branch was still being worked on in the main checkout, so the design was
  committed from a separate worktree. The reading work depends on the
  Presentation Coordinator landing first.

- Task 3 manual check, iPhone simulator (iPhone 18 Pro): Import through the
  file picker, Rename (dialog seeded with the Title, saves), Delete (confirms,
  removes), tapping a Cover pushes the placeholder screen, back returns, and
  the opened Book is first in the grid. **Still to check:** Mac (⌘I, drop,
  double-click and Return to open, Rename, Delete) and the iPad multi-delete
  ending select mode. Computer use was not available in the session when the
  Mac check was attempted. The owner then ran the Task 3 manual check by hand
  and reported "manually tested, and passed"; they did not itemise which
  checks, so the Mac and iPad items are recorded as passed on that report.
- The Mac "On My iPhone" folder of the iOS simulator is
  `group.com.apple.FileProvider.LocalStorage`, not the iCloud Drive container;
  Sources for manual checks go under its `File Provider Storage` folder.
- Task 5 manual check, iPhone simulator (iPhone 18 Pro), all passed: a Book
  opens on its Reading Position (Page 6 after Page 6 was left, across a
  relaunch with the Book still open: the Library shows, the card reads
  "Page 6 of 12" and the Book is first); swipe past the last Page does
  nothing; the slider jumps; a text file named `.png` shows the placeholder,
  counts as "Page 2 of 3", and the position moves onto it; double-tap and
  pinch zoom about the centre; a zoomed Page pans, and a swipe at its edge
  turns the Page (the hand-off needs no UIKit); the system back swipe from the
  left edge turns a Page instead of leaving; a one-Page Book reads "Page 1 of
  1" with the slider disabled and swipes doing nothing; Close returns and the
  card reads "Page 5 of 12" in first place. **Not checked by the builder:**
  the Mac screen (arrow keys, Escape, trackpad swipe, zoom hand-off) and the
  iPad; computer use was not available.
- The design and plan said a Page file is at `<folder>/<file name>`. It is at
  `<folder>/pages/<file name>`; every Page showed the placeholder until
  `pageURL` used `ImportPipeline.pagesName`.
- The scroll view does not keep a zoomed Page centred on its own; it needs
  `defaultScrollAnchor(.center, for: .sizeChanges)` as well as the initial
  anchor.
- Task 6 manual check, iPhone simulator: with a Book open, an Import that was
  queued behind a long one failed, and its Notice ("Couldn't Import “Empty”",
  "No images found") appeared as a dialog over the open Page; OK dismissed it
  and the Page was still there. The check used a real failing Import. The plan
  proposed a DEBUG-only hook that queues test Notices (`FOLIO_DEBUG_NOTICES=reading`);
  it was not added, because DECISIONS.md records that hook as a removed
  workaround and CLAUDE.md no longer describes it. **Not checked:** the
  status-line half (a status Notice at the bottom over the Page, then at the
  top of the Library after Close): no real action produces one on the reading
  screen without such a hook, and the Mac. The model-level check is the
  existing "a failing Import queues its Notice" test; the model has no notion
  of reading, so nothing in it can hold a Notice back.
- Gate: `./scripts/verify.sh` green on macOS and iOS (format, build, test,
  launch with screenshots).

## Commits

| Commit | Subject |
|--------|---------|
| f8685c1 | docs(design): reading a Book |
| c2a94d9 | docs(plan): implementation plan for reading a Book |
| d413de0 | feat(library): turnPage moves a Book's Reading Position |
| d8c29bf | feat(library): open regardless; turnPage and open record are log-only |
| a5d427a | refactor(library): LibraryWindow owns the navigation path and every dialog |
| 5065b02 | feat(reading): decode Pages downsampled, cache the current Page and its neighbours |
| 1d0ad87 | feat(reading): open a Book and turn its Pages |
| 6e298f8 | docs(reading): record the Notice-over-the-open-Book check |
| (task 7) | docs(reading): record the reading rulings |
