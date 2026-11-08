# Reading a Book — Design

Date: 2026-11-08
Status: ready for approval (revised after the builder check)
Glossary: `CONTEXT.md` is authoritative. Capitalised terms are glossary terms.

## Intent

Folio can import Books and show them in the Library, but tapping a Cover
today only records the open: nothing appears on screen. This slice adds the
act of reading. Opening a Book shows its Pages one per screen, turning Pages
moves the Book's Reading Position, and the Library grid reflects that
position and re-orders the Book accordingly.

The original design (`2026-11-08-folio-comic-reader-design.md`, "Reader")
already decided how the screen behaves. This document carries that over
unchanged and settles what it left open: the language, what the Library
hears, what persists, and how failures are treated.

## What the owner decided (this conversation)

- **A fresh launch always lands in the Library.** Folio never reopens the
  Book that was open when the process was killed. The Library owes the user
  only that the Book shows its Reading Position and sits first in the order.
- **If the app was not killed, the open Book stays open.** Backgrounding
  and returning, or switching apps, returns to the same Page.
- **Reading Position is written on every Page turn**, not on close, so a
  kill loses nothing.
- **Reopening lands on the Reading Position.** No prompt, no "resume?",
  no stepping back one Page. A Book never opened starts at its first Page.
- **There is no "finished" state.** Swiping past the last Page does
  nothing. The Library shows "Page 180 of 180" and reopening lands there.
- **A Page that cannot be decoded shows a broken-image placeholder** in its
  place. It keeps its position in the order, the Reading Position moves
  onto it like any other Page, and no Notice appears.
- **A failed save while reading is suppressed.** The Page turn itself
  visibly succeeds, so a failed Reading Position write is logged and not
  shown. Consequence the owner accepted: if writes keep failing, the user
  only finds out on the next open by landing on an older Page.
- **Opening is "open regardless".** A Book that the Library has opens even
  if recording the open fails; that failure is logged, not shown. The one
  exception is a Book the Library no longer has, which cannot open and
  keeps its Notice.
- **One glossary addition**: the event ReadingPositionChanged. BookOpened
  is now only the ordering fact. Already applied to `CONTEXT.md`.
- **A Notice shows over the open Book.** Imports keep running underneath
  reading, and an Import failure is something the user can act on, so it
  is not held until close. The owner's rule: Notices live at the root of
  the window, so every screen, present and future, is a subview of the
  thing that shows them (a tab bar in a tab app, the NavigationStack here).
- **The open Book is a pushed screen, not a full-screen cover**, on every
  platform. This follows from the rule above: SwiftUI presents a cover in
  a layer above the root, so a root-level Notice would not appear over it.

## Calls made by the designer (after the builder check)

- **An open Book belongs to its window on Mac.** The presenting state is
  per window (view state on the NavigationStack path), not on the shared
  `LibraryModel`. Opening a Book in one window changes nothing in another.
- **Opening a never-read Book sets its Reading Position to the first Page
  at once**, announcing ReadingPositionChanged. Look at page 1 and close,
  and the card reads "Page 1 of 180". This follows from the glossary: the
  Reading Position is the Page the reader was last on.
- **"Open" on Mac means double-click or Return on the selected Book.** No
  File menu item in this slice.

## Goals

- Tapping a Cover (iPhone, iPad), double-clicking it (Mac), or activating
  it from the keyboard or accessibility opens the Book on its Reading
  Position, or its first Page.
- Turning Pages moves the Reading Position; the Library grid shows it and
  re-orders the Book by the time the user returns.
- The screen behaves as the original design states: one Page per screen,
  horizontal swipe left to right, pinch and double-tap zoom, zoomed Pages
  pan until the edge, tap toggles chrome (Title, page counter, scrubber,
  close), chrome hidden by default, arrow keys and trackpad swipe on Mac.
- Pages decode lazily, downsampled to the screen, one ahead and one behind
  pre-decoded, so a 500-Page Book does not exhaust memory.
- Every Library operation this slice adds has a test that forces its
  failure and asserts what the user sees (here: nothing, and a log line).

## Non-goals

- Right-to-left, vertical scrolling, two-page spreads.
- Remembering zoom level or chrome state between opens.
- Reopening the last Book at launch (explicitly ruled out above).
- Any change to Import, Cover, Rename, or Delete.
- Thumbnails of Pages for the scrubber; the scrubber is a slider with a
  counter.

## Anti-goals

- A Notice lost unseen because the screen that would show it is off
  screen. (The Visible Failures slice fixed this class of bug; this slice
  must not reintroduce it.)
- The Library grid jumping while the user is still looking at it (the
  existing rule: order refreshes when the screen next appears, not live).
- Decoding every Page up front, or holding full-size images in memory.

## Domain model

### Values

Unchanged. `Book` already holds `pages: [Page]` in reading order and
`readingPosition: Int?`, a 0-based index into `pages` (`DECISIONS.md`:
"Reading Position is a 0-based index into the Book's Pages"). The UI shows
"Page n+1 of N".

### Invariants

- A Reading Position, when present, is in `0..<pages.count`. The Library
  rejects a move outside that range with `LibraryError.invalidStatus(.turnPage)`
  rather than storing it. (A Book always has at least one Page: Import
  refuses empty Sources.)
- A Reading Position is never cleared once set.

### Operations on the `Library` actor

Existing: `open(bookID:)` sets `lastOpenedAt`, announces BookOpened. Kept
as is.

New: `turnPage(bookID: BookID, to index: Int) async throws(LibraryError)`.
Sets the Book's `readingPosition` to `index`, saves, announces
`.readingPositionChanged(bookID, page: index)`. Throws only `LibraryError`,
naming a new operation `LibraryOperation.turnPage` ("Turn Page"). No event
when `index` equals the stored position (a repeated turn to the same Page,
as the scrubber can produce, is not a change).

### Event

New case `LibraryEvent.readingPositionChanged(BookID, page: Int)`.

`LibraryModel.handle` treats it like `.bookOpened` today: no reload, because
the order refresh waits for the Library screen to reappear. The Book's card
then shows the new position from the reload that already happens on
appear.

## Behaviour

### Opening

1. The user activates a Book card. The view asks the model to open it.
2. The model asks the Library to record the open. If that throws
   `.notFound`, the model queues the existing Notice and stops: the Book is
   not shown. Any other `LibraryError` is logged under `AppLog.library` and
   ignored, with a comment at the site referencing this design.
3. The view pushes the reading screen for the Book onto its window's
   NavigationStack path, starting on `readingPosition ?? 0`. On appear,
   if the Book had no Reading Position, the screen asks the model to
   `turnPage(to: 0)` so the position exists from the first open.

### Reading

- The screen holds the current Page index as view state. Each time it
  changes, it asks the model to `turnPage`, which calls the Library and
  logs any `LibraryError` without a Notice. Turns are serialised in order
  by the Library actor; a burst from the scrubber may produce several
  saves, and the last one wins.
- Swiping forward on the last Page or back on the first Page does nothing.
- A Page whose file cannot be decoded shows a placeholder (SF Symbol
  `photo.badge.exclamationmark` or similar, builder's choice) filling the
  Page area, with a hidden accessibility label "Page n could not be shown".
  The Page still counts and the Reading Position still moves onto it.
- Chrome: hidden on open. Tap toggles it. It shows the Title, "Page n of N",
  a slider over `0..<pages.count`, and a close control. On Mac the close
  control is also Escape; arrow keys turn Pages; the toolbar hosts the
  same controls per the HIG.
- Zoom: pinch and double-tap toggle between fit and a 2.5× scale (builder's
  call on the exact scale). A zoomed Page pans; a swipe at the edge of a
  zoomed Page turns it.

### Closing

Close pops the screen. Nothing is written on close; the Reading Position is already current. The Library screen's
existing on-appear reload refreshes the grid, so the Book moves to the
front and shows "Page n of N".

### Life cycle

- Background and return: the screen is still presented; the same Page
  shows. Nothing special is done.
- Process killed: next launch shows the Library, as today. Nothing
  restores the open Book.

### Platform adaptation

- iPhone: pushed onto the NavigationStack with the navigation bar hidden
  while the chrome is hidden. Status bar hides with the chrome. The
  system back swipe from the left edge is disabled while reading, since
  the left edge turns a Page; Close in the chrome is the way out.
- iPad: same push; honours Split View and Slide Over sizes, so "fit" is
  to the current window, not the device.
- Mac: the reading screen replaces the Library in the same window, via the
  NavigationStack; the toolbar carries the chrome controls; Escape closes;
  the Open command and double-click both open.

### Pages and memory

Pages are files under the Book's folder in the Books directory
(`LibraryStorage`), named by `Page.fileName`. The screen builds each Page's
URL from `booksDirectory/folderName/fileName` through the model, as the
Cover already does, and decodes with ImageIO downsampled to the current
window's pixel size. A small cache holds the current Page and one each side.
An undecodable file yields the placeholder; it is not an error the Library
hears about.

## Architecture

### FolioCore

- `LibraryEvent.readingPositionChanged(BookID, page: Int)`.
- `LibraryOperation.turnPage`.
- `Library.turnPage(bookID:to:)` with the range check, through
  `storageGuard(.turnPage)`.
- Tests: moves and announces; no event on an unchanged position; out of
  range throws `.invalidStatus(.turnPage)` and stores nothing; unknown Book
  throws `.notFound(.turnPage)`; a failing repository throws
  `.storage(.turnPage)` and stores nothing.

### App

- `LibraryModel`: `open(_:)` returns whether the Book may be shown
  (false only on `.notFound`, which queues the Notice); `turnPage(_:to:)`
  that logs failures; `pageURL(for:at:)`.
- Notices move to the root: the view that owns the NavigationStack
  presents the dialog Notice and the status Notice, reading the same
  `LibraryModel` queue, so a Notice appears over whichever screen is on
  top. `LibraryView` stops presenting Notices itself. The Import-request
  gate treats the open Book like any other screen: the picker still waits
  for the current dialog to close, not for the Book to close.
- The status Notice on the reading screen: shown at the bottom of the
  window over the Page, in the same style as on the Library, regardless
  of chrome state. It is a failure report, so it is never hidden with the
  chrome.
- A new `Reading/` folder under `app/Folio/` holding the reading screen,
  the Page view with zoom, the chrome, and the Page decoder/cache.
- `LibraryView` pushes the reading screen through the window's
  NavigationStack path on every platform.
- Tests: `open` on a missing Book queues the Notice and returns false;
  `open` on a storage failure returns true and queues no Notice;
  `turnPage` on a failing Library queues no Notice; an ImportFailed event
  arriving while a Book is open queues a Notice that is presented (not
  dismissed unseen), checked at the model level and by a UI test or a
  manual check noted in the log. Decoder tests: a non-image file yields
  the placeholder state, not a throw.

### Logging

New category `AppLog.reading` for the screen and decoder. Library-side
failures stay under `LibraryLog`.

### Strings

New user-facing strings go in `Localizable.xcstrings`: "Page %lld of %lld"
(already present on the card), "Close", "Page %lld could not be shown".

## Constraints

- Swift 6 strict concurrency; SwiftUI only. If a zoomable, pannable paged
  view cannot be built in SwiftUI without a wrapped `UIScrollView` /
  `NSScrollView`, the builder may wrap one and must record why in
  `DECISIONS.md`.
- No third-party dependencies.
- Warnings are errors; `./scripts/verify.sh` must pass on every platform.

## Decision log entries this slice must add

In `DECISIONS.md`, in the owner's plain language:

- Why a failed Reading Position write and a failed open record are
  log-only, with the accepted consequence stated.
- Why the app never restores the open Book at launch.
- Why Notices are presented at the root of the window, and why the open
  Book is therefore a push and not a cover.
- The zoom scale.

## Left to the builder

- Exact zoom scale, animation, and chrome layout within HIG.
- The placeholder symbol and its colour.
- The decode cache size beyond "current plus one each side".
- Whether the Mac toolbar hides with the chrome or stays.
