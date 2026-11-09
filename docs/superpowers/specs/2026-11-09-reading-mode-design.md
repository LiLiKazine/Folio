# Reading Mode — Design

Date: 2026-11-09
Status: ready for approval (revised after the builder check)
Glossary: `CONTEXT.md` is authoritative. Capitalised terms are glossary terms.
Builds on: `2026-11-08-reading-design.md` (the reading screen, Reading
Position, the log-only rulings for saves while reading).

## Intent

Today a Book reads one Page per screen, turned by a horizontal swipe. Some
Books carry pictures that run off the bottom of one Page onto the top of the
next; one Page at a time cuts them in two. This slice adds a second Reading
Mode, Vertical, in which every Page is stacked into one strip the reader
scrolls, so continuous pictures read as one. Each Book remembers which
Reading Mode the reader chose.

## What the owner decided (this conversation)

- **Two Reading Modes for now: Page by Page and Vertical.** Side by side
  (two Pages as an open book) was considered and dropped from this slice.
- **Each Book remembers its Reading Mode.** A Book that has none reads
  Page by Page.
- **The glossary gains one term, Reading Mode, and one event,
  ReadingModeChanged.** Already applied to `CONTEXT.md`. "Reading Mode"
  was chosen over "Layout" to keep clear of SwiftUI's layout vocabulary.
- **Reading Position keeps its meaning**, "the Page a reader was last on".
  In Vertical the Page you are "on" is the one at the top of the screen
  (mechanism, see below).
- **Switching keeps your place.** The Page you were on in one Reading Mode
  is the Page you land on in the other.
- Accepted as described, with the designer's guesses marked at the time:
  Pages fill the screen's width and touch with no gap; pinch zooms the
  whole strip; reopening in Vertical lands at the top of the Reading
  Position's Page, not the exact pixel.
- **Tall Pages are handled the way the open-source readers do it** (the
  owner asked for prior art rather than a choice between blur and
  memory): decode at screen width for sharpness, cut the decoded Page
  into slices so no single huge image reaches the screen, and keep the
  decoded Pages within a byte budget. See "Tall Pages" below.
- **Which Page you are "on" in Vertical is the Page at the top of the
  screen**, not the middle. The builder check showed the middle rule and
  top-aligned jumps fight each other when Pages are shorter than half the
  screen. Accepted by the owner.

## Calls made by the designer

- **A failed Reading Mode save is log-only**, like a failed Reading
  Position save in the reading design. The switch itself visibly succeeds
  on screen. Consequence the owner should know: if the save fails, the
  Book opens in its previous Reading Mode next time. The site carries the
  comment the Visible Failures rule requires, pointing at this design.
- **Arrow keys on Mac turn Pages in both Reading Modes.** In Vertical,
  left and right jump to the top of the previous or next Page; up, down,
  Page Up, Page Down and the scroll wheel scroll the strip as any Mac
  scroll view does.
- **The slider and counter work the same in Vertical**: the counter shows
  the Page at the top of the screen; moving the slider scrolls so
  that Page's top sits at the top of the screen.
- **The Reading Mode control lives in the chrome**, shown and hidden with
  it, as a toolbar item on every platform (builder's placement within
  HIG). It offers the two Reading Modes by name, "Page by Page" and
  "Vertical", and shows which is current.
- **Pages are never decoded larger than their own pixels.** Screen width
  is a ceiling, not a target: an 800-pixel-wide Page on a 1,179-pixel
  screen is decoded at 800 and scaled up by the display.
- **Every Page in the strip has its height fixed before it is decoded**,
  from the image's pixel size read through ImageIO without decoding, so
  the strip does not jump as Pages load. A Page whose size cannot be read
  (the file is not an image) takes a square the width of the strip and
  shows the existing placeholder.

## Goals

- From the open Book's chrome, choose Vertical; the Pages become one strip,
  width-fitted, touching, scrolled by finger, wheel, trackpad or keys.
- The Book remembers the choice: closing and reopening, or relaunching,
  opens it in Vertical at the Reading Position's Page. Another Book is
  unaffected.
- Switching back to Page by Page shows the Page that was at the top of
  the screen.
- Scrolling the strip moves the Reading Position exactly as turning Pages
  does: the Library card shows "Page n of N" for the Page last at the top
  of the screen, and reopening lands on it.
- Pinch zoom on the strip, from fit-to-width up to the same maximum scale
  as a single Page, panning sideways when wider than the screen; double
  tap toggles between fit and the existing zoomed scale.
- Tall Pages are sharp at the screen's width, and memory stays within a
  stated budget however tall they are.
- Every Library operation this slice adds has a test that forces its
  failure and asserts what the user sees (here: nothing, and a log line).

## Non-goals

- Side by side (two-Page spreads), right-to-left, a gap or separator
  between Pages, per-Book zoom memory.
- A Library-wide default Reading Mode or a setting that changes it.
- Showing the Reading Mode on the Library card.
- Any change to Import, Cover, Rename or Delete.

## Anti-goals

- The strip jumping under the reader's finger as Pages decode.
- The Reading Position flickering between two Pages while the reader
  rests on a boundary (the rule below resolves ties one way).
- A Book of one Reading Mode opening in another because a save was lost
  silently with no log line.
- Decoding every Page of a long Book because the strip is one view.

## Domain model

### Values

New `public enum ReadingMode: String, Codable, Sendable, CaseIterable`
with cases `pageByPage` and `vertical`, in `FolioCore/Domain`.

`Book` gains `public var readingMode: ReadingMode`, defaulting to
`.pageByPage` for every Book that has not chosen. The glossary's "a Book
that has none" is represented by this default, not by an optional: nothing
in the product distinguishes "never chose" from "chose Page by Page".

### Invariants

- A Book always has a Reading Mode; the default is Page by Page.
- Reading Position's invariant is unchanged: in `0..<pages.count`, never
  cleared once set.

### Operations on the `Library` actor

New: `chooseReadingMode(bookID: BookID, _ mode: ReadingMode) async throws(LibraryError)`.
Sets the Book's `readingMode`, saves, announces
`.readingModeChanged(bookID, mode:)`. Throws only `LibraryError`, naming a
new `LibraryOperation.chooseReadingMode` ("Choose Reading Mode"). Choosing
the Reading Mode the Book already has changes nothing and announces
nothing, like `turnPage`.

`turnPage` is unchanged: Vertical calls it with the Page at the top of the
screen whenever that Page changes.

### Event

New case `LibraryEvent.readingModeChanged(BookID, mode: ReadingMode)`.
`LibraryModel.handle` treats it like `.readingPositionChanged`: no reload.

## Behaviour

### Opening

As today, plus: the reading screen starts in the Book's Reading Mode. In
Vertical it starts scrolled so the Reading Position's Page has its top at
the top of the screen (the first Page if the Book has none).

### Reading in Vertical

- One vertical scroll view, Pages in reading order, no spacing. Each Page
  is laid out at the strip's width and at the height that keeps its pixel
  aspect ratio, computed from ImageIO properties before any decode.
- **Which Page is "on"**: the last Page whose top edge is at or above the
  top of the visible area; a Page whose top is exactly at the top counts.
  When the strip is scrolled to its very end, the last Page is "on"
  whatever its top. Before the first Page (bounce) the first Page is
  "on". So every jump lands you on the Page you asked for, switching
  keeps your place, and "Page 180 of 180" is reachable. The screen asks
  the model to `turnPage` each time this Page changes, exactly as the
  pager does on a swipe. The Library already drops repeats, so a burst of
  scroll events costs no writes beyond one per Page crossed.
- Decode: see "Tall Pages". Prefetch covers the Page at the top and its
  neighbours (builder's call how many, at least one each side, more when
  Pages are shorter than the screen).
- A tap toggles the chrome; a double tap toggles zoom; a pinch zooms.
  Zoom scales the whole strip's width; the scroll view then scrolls
  sideways as well as down. Fit is scale 1; the maximum is the single
  Page's maximum. Letting go below fit snaps back to fit.
- Reaching the end: the strip stops at the bottom of the last Page.
  Nothing marks the Book finished (reading design: no finished state).

### Tall Pages

The Pages this slice exists for can be very tall and narrow (a continuous
picture may be 800 by 12,000 pixels or more). Three facts shape how they
are shown:

- Decoding to the window's longer side, as Page by Page does, makes a tall
  Page blurry once it is stretched to the screen's width.
- Decoding to the screen's width makes one such Page tens of megabytes,
  and the Pages near the screen add up.
- A single image taller than the GPU's texture limit (8,192 or 16,384
  pixels, by device) is not safe to hand to the screen as one piece.

Prior art, read for this design: Aidoku (iOS, Swift) decodes each Page
with ImageIO to the screen's width with no height bound and relies on its
image cache's byte limit. Mihon (Android) decodes each Page once at the
view's width, lowered when the Page would exceed 128 MB, then cuts the
decoded Page into strips of about 4 MB so only the strips on screen reach
the GPU, frees the strips of large Pages when they leave the screen, and
decodes one Page at a time. Mihon removed its earlier "split tall images
at download" setting in favour of this.

Folio does the same as Mihon, in SwiftUI:

- **Width.** A Page is decoded to the smaller of its own width and the
  screen's width in pixels, lowered further if the result would exceed
  the per-Page budget below. Never wider than its own pixels.
- **Slices.** The decoded Page is cut into horizontal slices of bounded
  height (builder's call: a height that keeps each slice under the GPU
  limit and around 4 to 8 MB). The strip lays the slices out edge to
  edge, so the reader sees one Page. The whole decoded image is freed
  once its slices exist, so only slices live in memory.
- **Budget.** A per-Page budget (designer's starting value: 96 MB on
  iPhone and iPad, 256 MB on Mac; builder may tune from measurements) and
  a whole-cache budget (designer's starting value: three Pages' worth of
  slices at the per-Page budget, always including the Page at the top of
  the screen and the one after it). Pages beyond the budget are released
  and decoded again when they come back; their frames keep their size, so
  the strip never moves.
- **One decode at a time.** Decodes are serialised so two tall Pages are
  never fully decoded at once.
- **Page by Page is unchanged** in this slice: it keeps decoding to the
  window's longer side as one image. A tall Page in Page by Page was
  already fitted to the screen and is not this slice's concern.

### Switching

- The chrome's Reading Mode control sets the mode. The screen asks the
  model to `chooseReadingMode`; the model asks the Library and logs any
  `LibraryError` without a Notice (see the call above).
- The screen switches at once, without waiting for the save, and carries
  the current Page across: to Vertical, scrolled so that Page's top is at
  the top; to Page by Page, showing that Page. Zoom resets to fit on a
  switch.

### Reading in Page by Page

Unchanged.

### Platform adaptation

- iPhone and iPad: Vertical scrolls with the finger; the status bar and
  navigation bar follow the chrome as today. The system back swipe stays
  disabled; Close is the way out.
- Mac: wheel, trackpad, arrow keys and Page keys scroll; left and right
  arrows jump a Page; Escape closes. The Reading Mode control is also
  reachable from the toolbar when the chrome is shown.

## Architecture

### FolioCore

- `Domain/ReadingMode.swift`: the enum.
- `Book.readingMode` with default; `Book.init` gains the parameter with a
  default value so existing call sites compile.
- `LibraryEvent.readingModeChanged(BookID, mode: ReadingMode)`.
- `LibraryOperation.chooseReadingMode`.
- `Library.chooseReadingMode(bookID:_:)` through `storageGuard`.
- Tests: chooses and announces; no event when unchanged; unknown Book
  throws `.notFound(.chooseReadingMode)`; a failing repository throws
  `.storage(.chooseReadingMode)` and stores nothing; a Book decoded without
  the field reads Page by Page.

### App: persistence

- `BookModel` gains `readingMode: String?`; nil maps to `.pageByPage`, an
  unknown string also maps to `.pageByPage` (a newer build wrote a mode
  this build does not know; reading the Book must not fail).
- Per `FolioSchema.swift`'s own instruction, freeze V1's models, add
  `FolioSchemaV2` with the new field, and a lightweight migration stage
  from V1 to V2. Adding an optional attribute is within SwiftData's
  lightweight migration (Apple: "Lightweight migrations ... adding a new
  attribute with a default value or optional"); the builder confirms the
  store opens on a V1 fixture.

### App: Library

- `LibraryModel.chooseReadingMode(_:_:)`, log-only on failure with the
  required comment; `handle` adds the event case beside
  `.readingPositionChanged`.

### App: Reading

- `ReadingView` becomes the host for both Reading Modes: it owns `index`,
  the chrome, the cache, the toolbar and the keys, and shows either the
  existing pager or a new `VerticalStripView` by the Book's Reading Mode
  (held as view state seeded from the Book, updated when the reader
  chooses).
- `VerticalStripView`: the scroll view, Page frames from sizes, the
  top-of-screen rule writing back to `index`, programmatic scrolling
  to a Page's top when `index` is set from outside (slider, keys, switch,
  open), zoom.
- `PageImageCache` (or a sibling) gains `pixelSize(at:) async -> CGSize?`
  read through `CGImageSourceCopyPropertiesAtIndex` without decoding.
- A sliced decode for Vertical: decode once with ImageIO
  (`CGImageSourceCreateThumbnailAtIndex`, `kCGImageSourceThumbnailMaxPixelSize`
  set so the width lands on the chosen value), cut into slices with
  `CGImage.cropping(to:)` or by drawing into slice-sized contexts, free
  the whole image, hold the slices under the budgets above, serialised
  through one actor. Lives beside `PageImageCache` in `Reading/`.
- `ReadingChrome` gains the Reading Mode control, or the toolbar does;
  builder's call within HIG.
- Scroll mechanics must rest on documented SwiftUI behaviour: candidates
  are `scrollPosition(id:anchor:)` with a top anchor, or
  `onScrollGeometryChange` with the known Page frames. The builder reads
  Apple's documentation for the one chosen and quotes it in the
  implementation log; no timers, no delays, no polling.
- Tests: the top-of-screen rule as a pure function over Page heights, an
  offset and a viewport height (a top exactly at the top counts; before
  the first Page gives the first; at the end of the strip gives the
  last); the decode width rule (own width, screen width, budget) as a
  pure function; slicing a known image yields slices whose heights sum to
  the whole and none above the bound; the cache releases beyond its
  budget and keeps the top Page and the next; `startIndex` unchanged; a
  non-image file yields no size; a V1 store opens and its Books read
  Page by Page.

### Strings

New user-facing strings in `Localizable.xcstrings`: "Reading Mode",
"Page by Page", "Vertical", and any accessibility labels the control
needs. Sync the catalog as `CLAUDE.md` describes.

## Constraints

- Swift 6 strict concurrency; SwiftUI only. If strip zoom cannot be done
  in SwiftUI with the scaled-frame technique `PageView` already uses, the
  builder may wrap a platform scroll view and must record why in
  `DECISIONS.md`.
- No third-party dependencies; `./scripts/verify.sh` green on every
  platform; warnings are errors.
- Glossary terms exactly; none of the `_Avoid_` words in code, copy, tests
  or commits.

## Decision log entries this slice must add

In `DECISIONS.md`, in the owner's plain language:

- Why Reading Mode is remembered per Book with no Library-wide default.
- The top-of-the-screen rule for which Page you are "on" in Vertical,
  with the end-of-strip rule, defined before it is used, and why the
  middle rule was dropped.
- How tall Pages are shown (width, slices, budget, one at a time), what
  the reader would notice (a Page that left the screen and comes back may
  take a moment to appear) and the prior art it follows.
- Why a failed Reading Mode save is log-only and what the user would
  notice.
- Why Page heights are fixed from image sizes before decoding.
- Why the store moved to schema V2 and what a V1 store experiences
  (nothing visible; every Book reads Page by Page).

## Left to the builder

- The control's form (menu, segmented control, toggle button) and toolbar
  placement per platform.
- The prefetch window in Vertical, the slice height, and the budgets
  after measuring on a real tall Book.
- The exact scroll mechanism, provided it is documented behaviour.
- Animation on switching and on programmatic scrolls.
