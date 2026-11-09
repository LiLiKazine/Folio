# 2026-11-09-01: Reading Mode — design rulings

**Status:** Decided; implemented, owner's manual checks pending

## Context

A Book reads one Page per screen, turned by a swipe. Some Books carry
pictures that continue from the bottom of one Page onto the top of the next,
and one Page at a time cuts them in two. The owner asked for "more ways of
reading", and the design was walked through with the glossary in hand (settle
the words first, then the behaviour). Design:
`docs/superpowers/specs/2026-11-09-reading-mode-design.md`.

Terms used here: a *strip* is every Page of a Book stacked top to bottom into
one scrolling column; a *slice* is a horizontal band cut from a decoded Page
so that no single very tall image is handed to the screen in one piece;
*decoding* is turning a Page's file into pixels; a *budget* is the most memory
decoded Pages may use at once; *log-only* means a failure is written to the
system log and the user sees nothing.

## Options

| Question | Chosen | Rejected and why |
|----------|--------|------------------|
| Which new ways of reading | Vertical only | Side by side (two Pages as an open book): the pairing goes wrong when a scan has no cover, and the owner dropped it for now |
| How a Book ends up in a way of reading | Each Book remembers its own; none means Page by Page | Pick each time, or guess from the Book: the owner wants it remembered |
| The term | Reading Mode | Layout: collides with SwiftUI's own layout vocabulary in every file; Reading Layout was offered and the owner chose Reading Mode |
| Which Page you are "on" in Vertical | The Page at the top of the screen; at the very end of the strip, the last Page | The Page under the middle of the screen: with Pages shorter than half the screen, jumps landed on a different Page than asked, the slider sprang forward, switching lost your place, and the last Page was never reachable (found by the builder check) |
| Tall, narrow Pages | Decode at screen width, cut into slices, keep within a budget, one decode at a time (what Mihon does; Aidoku does the first step) | Decode to the window's longer side as Page by Page does: blurry. Decode at screen width whole: tens of MB per Page and over the GPU texture limit. A third-party library: none does this; image loaders do not slice, tiled viewers show one image not a strip, are UIKit, years old, and one crashes inside SwiftUI on iOS 26 |
| A failed Reading Mode save | Log-only, like a failed Reading Position save | A Notice: the switch itself visibly succeeded. Accepted cost: the Book opens in its previous Reading Mode next time |
| Heights of Pages in the strip | Fixed from the image's pixel size before decoding | Measured after decoding: the strip would jump under the finger |

## Decision

Add one glossary term, Reading Mode (Page by Page, Vertical), one event,
ReadingModeChanged, and one Library operation that chooses a Book's Reading
Mode; show Vertical as a strip whose Pages are decoded at screen width in
slices within a memory budget.

## Rationale

The owner's goal is continuous pictures reading as one, which only Vertical
gives. Remembering per Book matches how Reading Position already works. The
tall-Page approach follows the two most used open-source readers rather than
inventing one, and stays within the project's SwiftUI-only, no-dependency
rules because each step is one Apple framework call.

## What Changed

- `CONTEXT.md`: Reading Mode term; ReadingModeChanged event.
- `docs/superpowers/specs/2026-11-09-reading-mode-design.md`: the design.

## What Was Discovered

- Mihon removed its "split tall images when downloading" setting in favour of
  slicing at display time; the slicing exists so a tall Page never becomes one
  GPU texture.
- Aidoku decodes to screen width with ImageIO's thumbnail call and no height
  bound, relying on its cache's byte limit.
- Git's `includeIf hasconfig:remote.*.url` stopped matching this repo after
  Xcode Cloud setup changed the fetch URL to https, so commits would have
  been authored as the work identity. Fixed with a repo-local
  `include.path` to the personal config.

## Implementation

Built on `feature/reading-mode`. It differs from the design and plan in three
ways the reader can notice: the strip is a plain stack rather than a lazy one,
so every Page sits exactly at its known height; every Page's size is read
before the strip appears, rather than Pages starting as squares; and only the
reader's own scrolling (dragging or coasting) moves the Reading Position, so
opening, switching, the slider and the keys never do. Why, with Apple's text
and the measurements: `docs/logs/2026-11-09-02-reading-mode-implementation.md`.

## Commits

| Commit | Subject |
|--------|---------|
| 045de32 | docs(reading): add Reading Mode to the glossary and record its design |
| 7d34f5f | docs(reading): implementation plan for Reading Mode |
| a1e290d | feat(library): Books remember a Reading Mode; chooseReadingMode announces ReadingModeChanged |
| ddf450e | feat(persistence): schema V2 stores a Book's Reading Mode; the model chooses it log-only |
| 0bc1bae | feat(reading): strip geometry rule, pixel sizes, width rule, slices and a budgeted cache for Vertical |
| 4d69086 | fix(reading): the cache applies its budget after every decode, not once after a prefetch |
| 1012734 | feat(reading): Vertical Reading Mode as one strip of touching Pages, chosen from the chrome |
| 43f8746 | fix(reading): the strip counts only the reader's scrolling, keeps their place inside a Page when zoomed, and snaps Page heights to the pixel grid |
| 466ac34 | fix(reading): double tap zoom keeps the reader's place by not animating the size change |
| (this) | docs(reading): record the Reading Mode rulings and the owner's check list |
