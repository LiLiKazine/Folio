# 2026-11-08-06: Reading a Book — design rulings

**Status:** Decided; not yet implemented

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

## Commits

| Commit | Subject |
|--------|---------|
| f8685c1 | docs(design): reading a Book |
| c2a94d9 | docs(plan): implementation plan for reading a Book |
| d413de0 | feat(library): turnPage moves a Book's Reading Position |
| (task 2) | feat(library): open regardless; turnPage and open record are log-only |
