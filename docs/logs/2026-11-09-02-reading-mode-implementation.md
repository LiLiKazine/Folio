# 2026-11-09-02: Reading Mode — implementation

**Status:** Implemented; the owner's manual checks are pending. Nothing on the
Mac, on an iPad or on a real device has been checked.

## Summary

A Book can now be read Vertical as well as Page by Page. In Vertical every Page
of the Book sits under the one before it at the screen's width, touching, in
one column the reader scrolls (the *strip*). Each Book remembers the Reading
Mode the reader last chose for it; every Book saved before this version reads
Page by Page. In Vertical the Page at the top of the screen is the Page the
counter shows, the Page the Library card shows, and the Page reopening lands
on. Very tall Pages are decoded (turned from their stored data into pixels) at
the screen's width and cut into bands, so they are sharp and stay within a
stated amount of memory. The Reading Mode is chosen from a control shown with
the other reading controls: a row of two buttons in the Mac toolbar, and a menu
button in the iPhone and iPad navigation bar.

Verified: the FolioCore and app tests pass on iOS and macOS (`verify.sh`
without its launch step), and every item in Task 4's "Simulator checks" was
seen working on the iPhone 17 Pro simulator, iOS 26.5, including zoom deep in
the strip and the defects found in review, once fixed.

Not verified:

- Anything on the Mac. During Task 4 an agent's attempt to check the Mac app
  sent keystrokes to the owner's Mac, and they landed in another window
  (apparently a terminal). Since then no input of any kind was sent to the Mac
  (ruling 7).
- Turning an iPhone or iPad while reading Vertical.
- Anything on an iPad, or on a real iPhone, including smoothness and memory in
  a Book of 1,000 or more Pages. Every figure in this log is from the
  simulator or the Mac.
- A Library saved by an installed earlier build of the app. The upgrade was
  checked with saved data written by a test.

All of these are on the owner's check list below.

## Context

The design rulings are in `docs/logs/2026-11-09-01-reading-mode-design.md`;
the design is `docs/superpowers/specs/2026-11-09-reading-mode-design.md` and
the plan is `docs/superpowers/plans/2026-11-09-reading-mode.md`. This one log
collects what each implementation task changed, what it measured, and what it
could not check. Terms: a *stored Book* is a Book already saved on the device
by an earlier version of the app; *stand-in storage* is storage that keeps
Books in memory only and is used by tests in place of the real storage; a
*schema* is the description of how the Library's saved data is laid out on
the device, and a *migration* is the app upgrading data saved under an older
schema when it first opens it. The *store* is the file on the device that
holds that saved data. *Decoding* is turning a Page's stored data into pixels
the screen can show. *Log-only* means a failure is written to the system log
and the user sees nothing. The *chrome* is the Title, counter, slider, Close
and Reading Mode controls that a tap shows or hides over the Page. A *point* is
the unit SwiftUI (Apple's screen-building framework) measures the screen in;
an iPhone has 3 pixels per point, most Macs 2. *Fit* is the zoom at which a
Page fills the screen's width.

## The owner's manual check list

Each line says what to do and what you should see. "Seen on the simulator"
marks what an agent already saw on the iPhone 17 Pro simulator; nothing else
has been tried by anyone. The generated test Books used on the simulator are
in a temporary folder that may since have been cleared:
`/private/tmp/claude-501/-Users-leo-Developer-Folio/2b647ec0-073d-40c0-8b4f-1235ca57bf1a/scratchpad/books`.
Strip Mixed has 24 Pages, with a 600 x 12,000 pixel Page as Page 7, and a
Page 5 that holds text, not a picture, though it is named like one; Strip Short has 12 Pages wider than they
are tall; Strip Thousand has 1,000 small Pages. Any Book with a very tall Page,
and any Book of landscape pictures, will do as well.

### Mac (nothing checked)

1. Open a Book, click the Page once to show the controls (the Reading Mode control is in the toolbar only while they are shown), and choose "Vertical" in it: the Pages become one strip at the window's width with no gaps between them, and the control shows "Vertical".
2. Scroll the strip with the mouse wheel, then with two fingers on the trackpad: the strip moves, and the counter at the bottom changes to each Page as its top passes the top of the window.
3. Close the Book: its card in the Library reads "Page n of N" for the Page the counter showed last.
4. Reopen the Book, then quit Folio, relaunch it and reopen the Book again: both times it opens in Vertical with that Page's top at the top of the window, and a Book you did not switch still opens Page by Page.
5. In a Book whose Pages are all wider than they are tall, make the window narrow enough that two or more Pages fit in its height at once (or use a Book of small Pages), choose Vertical while on Page 5, then close and reopen it: Page 5 is at the top and the counter reads Page 5.
6. Scroll slowly through a very tall Page: it is sharp all the way down, with no visible join between its bands, and the app keeps responding while you scroll.
7. While on any Page in Vertical, choose "Page by Page": the same Page is shown.
8. In Vertical press the left and right arrow keys: the strip jumps to the top of the previous or next Page and the counter follows; in Page by Page they turn Pages as before.
9. In Vertical press the up and down arrow keys, then Page Up and Page Down, and note whether the strip scrolls at all and, if it does, whether the counter follows (nothing in the app passes these keys to the strip, the reading screen holds the keyboard, and Apple does not say whether keyboard scrolling counts as the reader scrolling).
10. Press Escape while reading in Vertical: the Book closes.
11. While part-way down a tall Page in Vertical, drag the window's edge to make it wider and narrower: the part of the Page you were looking at stays at the top of the window, the Pages are sharp again when you stop, and note whether the resize stutters (the Pages are decoded again at every new width while you drag).
12. In the middle of a tall Page, pinch on the trackpad and then double-click: the part you were looking at stays at the top of the window, the strip is centred left to right, and a second double-click goes back to fit.
13. Scroll to the very end of a Vertical Book, close it and reopen it: the strip ends exactly at the bottom of the last Page.
14. With a Library made by the previous version of Folio (for example a build of the main branch from before this work), run this version over it without deleting the app's data: every Book is still there with its Cover, its card shows the same "Page n of N" as before, and each Book opens Page by Page.

### iPhone (simulator only; nothing tried on a real iPhone)

1. Open a Book, tap to show the chrome, tap the Reading Mode button (the book symbol) in the navigation bar and choose "Vertical": the Pages become one strip, and the menu shows Vertical ticked. Seen on the simulator.
2. Swipe up and down: the counter changes to each Page as its top passes the top of the screen, and a tap, or a press held without moving, never changes it. Seen on the simulator for four taps and a one-second press; the simulator never reported a finger resting before a scroll begins (the case ruling 13 is about), so that case rests on Apple's description.
3. Close the Book: its card reads "Page n of N" for the Page the counter showed last. Seen on the simulator.
4. Reopen the Book, then quit Folio, relaunch it and reopen the Book: both times it opens in Vertical with that Page's top at the top of the screen. Reopening seen on the simulator; relaunching not recorded.
5. In a Book whose Pages are all wider than they are tall, choose Vertical while on Page 5, then close and reopen it: Page 5 is at the top and the counter reads Page 5. Seen on the simulator.
6. On a real iPhone, scroll slowly through a very tall Page: it is sharp all the way down, with no visible join between its bands, and scrolling stays smooth; if you run Folio from Xcode, note the memory its gauge shows while that Page is on screen (no figure from a device exists yet).
7. While on any Page in Vertical, choose "Page by Page": the same Page is shown. Seen on the simulator.
8. Deep in a long Vertical Book (past Page 20 of Strip Mixed), turn the phone sideways and back: you stay on the same Page at the same place in it (not checked; turning is an animated size change, and an animated zoom once landed the reader on the wrong Page, possibly for the same reason).
9. On a real iPhone, in the middle of a tall Page, pinch while also moving your two fingers, then pinch to zoom out past fit: the part you were looking at stays under the top of the screen while you pinch, and zooming out stops at fit, so the strip never becomes narrower than the screen (a plain pinch was seen on the simulator; moving while pinching and zooming out past fit were not).
10. Zoom in, pan sideways to one edge, then pinch or double tap again: the strip goes back to the middle, left to right, on every zoom step (known and expected; say if it gets in the way).
11. Deep in the strip, double tap: it zooms in at once, without an animation, centred and at the same place, and a second double tap goes back to fit. Seen on the simulator.
12. On a real iPhone, open a Book of 1,000 or more Pages in Vertical and scroll fast for a long way: the blank moment before the strip appears is short, scrolling stays smooth, and the system does not close the app for using too much memory (on the simulator: 0.06 to 0.22 s before the strip appeared, and 67 MB after a long scroll).
13. Scroll to the very end of a Vertical Book, close it and reopen it: the strip ends exactly at the bottom of the last Page. Seen on the simulator.
14. With the previous version of Folio installed and a Library in it (some Books part-read), install this version over it without deleting the app: every Book is still there with its Cover, its card shows the same "Page n of N" as before, and each Book opens Page by Page.

### iPad (nothing checked on an iPad or its simulator)

1. Do every iPhone item above on an iPad: you should see the same.
2. While part-way down a tall Page in Vertical, turn the iPad, and resize its window if you use iPad windows: the same Page stays at the top, at the same place in it.

## Task 1: Reading Mode in FolioCore

### What Changed

- `Domain/ReadingMode.swift` (new): `ReadingMode`, either `pageByPage` or
  `vertical`.
- `Domain/Book.swift`: a Book has a `readingMode`, defaulting to
  `pageByPage`. The code that reads a Book back from its saved form
  (`Book.init(from:)`) was written out by hand, so a Book saved without a
  Reading Mode (every stored Book) reads back as Page by Page; the code that
  writes a Book into its saved form is still the one Swift writes
  automatically, unchanged apart from the new field.
- `Domain/LibraryEvent.swift`: `readingModeChanged(BookID, mode:)`.
- `Library/LibraryError.swift`: `LibraryOperation.chooseReadingMode`
  ("Choose Reading Mode"), so a failed save can name what the user was doing.
- `Library/Library.swift`: `chooseReadingMode(bookID:_:)`, built like
  `turnPage`: it reads the Book, stops quietly if the Book already has that
  mode (no save, no event), otherwise saves and announces
  `readingModeChanged`. A failed read or save throws
  `storage(.chooseReadingMode)`; an unknown Book throws
  `notFound(.chooseReadingMode)`.
- `app/Folio/Library/LibraryModel.swift` (one word added to a list, ruling 5): `handle`
  lists `.readingModeChanged` beside `.bookOpened, .readingPositionChanged`
  so the app still compiles. It does nothing with the event yet; Task 2 does.

### Tests

- `LibraryTests`: choosing Vertical stores it and announces
  `readingModeChanged`; choosing the stored mode announces nothing and does
  not save; an unknown Book throws `notFound(.chooseReadingMode)`; a Book
  saved without `readingMode` reads back as Page by Page and equals the Book
  it was made from; a Vertical Book is saved and read back unchanged.
- `LibraryErrorTests`: `chooseReadingMode` joins the operation switch and the
  forced-storage-failure cases (`books`, `update`), so a failing save is
  proven to throw `storage(.chooseReadingMode)`.

### What Was Discovered

- Neither stand-in storage keeps a list of the calls made to it. "Does not
  save" is therefore shown by making every Book save fail (`update` throws) and showing that
  choosing the stored mode still succeeds, which it could not if it saved.
  The other `LibraryTests` events checks assert on events only.
- Test run before the code existed failed to compile (`LibraryOperation` has
  no member `chooseReadingMode`; `Library` has no member
  `chooseReadingMode`), as expected.

### Gate

- FolioCore: `swift test --package-path app/FolioCore -Xswiftc
  -warnings-as-errors`: 90 tests in 8 suites passed.
- `./scripts/build.sh macos`: build succeeded with the one-word app change.
- `./scripts/format.sh --check`: clean.
- App tests and iOS build not run for this task (the app change is the one word added to a list).

### Not checked

- No Apple documentation is relied on by this task (it is domain code only).

## Task 2: Persistence V2 and the model's log-only choose

### What Changed

- `Persistence/BookModel.swift`: the stored Book has a `readingMode` field,
  text that may be empty. Saving writes the Book's Reading Mode; reading maps
  the text back, and empty text or text that names no Reading Mode reads as
  Page by Page (the design's rule for unknown values).
- `Persistence/FolioSchema.swift`: `FolioSchemaV1` is now *frozen* (kept
  exactly as the earlier version saved data, never to be edited), with its own
  copies of the two stored shapes (`FolioSchemaV1.BookModel` and
  `FolioSchemaV1.ImportModel`) inside it. `FolioSchemaV2` is the current
  schema: the same two shapes with the new field on the Book.
  `FolioMigrationPlan` lists both schemas and one *stage* (one upgrade step
  between two versions of the saved data): a *lightweight* stage from V1 to
  V2, one for which SwiftData (Apple's storage framework) carries the data
  across itself. That it does so here, for one added optional field and with no
  code of ours running, is observed, not documented (see "What the
  documentation does not say" below).
- `Persistence/LibraryStorage.swift`: the real container (SwiftData's object
  that opens the store) is built from `FolioSchemaV2`. The on-disk path is now `makeContainer(at:)`, so a test can
  open a store file it wrote earlier; `makeContainer(inMemory:)` is unchanged
  for callers.
- `Library/LibraryModel.swift`: `chooseReadingMode(_:_:)` asks the Library to
  save the choice. If saving fails it is logged and no Notice is queued, with
  the owner's comment at the `catch` ("Log-only by the owner's ruling ...").
  `.readingModeChanged` was already listed in `handle` by Task 1.

### Apple documentation relied on

Fetched from `developer.apple.com/tutorials/data/documentation/swiftdata/...json`
on 2026-11-09. Apple's reference pages for these types are one-line summaries;
that is all they say:

- `VersionedSchema`: "An interface for describing a specific version of a
  schema, including the models it contains." Its `models`: "The models to
  include in this version of the schema." Its `versionIdentifier`: "The
  textual description of the migration's version or purpose." (`.../versionedschema.json`,
  `.../versionedschema/models.json`, `.../versionedschema/versionidentifier.json`)
- `SchemaMigrationPlan`: "An interface for describing the evolution of a
  schema and how to migrate between specific versions."
  (`.../schemamigrationplan.json`). Its page groups `schemas` under "Managing
  versioned schemas" and `stages` under "Managing migration stages"; the two
  members have no description text.
- `MigrationStage`: "Describes a migration between two versions of the same
  schema." (`.../migrationstage.json`). It lists `lightweight(fromVersion:toVersion:)`
  and `custom(...)` under "Migration stages"; the `lightweight` page gives only
  the signature `case lightweight(fromVersion: any VersionedSchema.Type, toVersion: any VersionedSchema.Type)`.
- `ModelContainer.init(for:migrationPlan:configurations:)`: "Creates a model
  container using the specified schema, migration plan, and zero or more
  configurations." (listed on `.../schemamigrationplan.json`)

### What the documentation does not say

Apple's pages do not say (a) that a lightweight stage covers an added optional
field, or (b) that the stored shapes may be nested inside the version enum.
Both are therefore marked as observed, and the evidence is the test
`v1StoreOpensAsPageByPage`: it writes a store file on disk with the frozen V1
schema (a Book with Pages and a Reading Position, saved with the V1 copy of
the Book shape), closes it, opens the same file through the real
`makeContainer(at:)`, and checks the Book is there, unchanged, and reads as
Page by Page. It passes on macOS and on the iOS simulator.

Also observed: with the migration plan's *stage list* (its list of upgrade
steps) temporarily emptied, the same test still passed, so SwiftData opened the
V1 file in the V2 schema without the stage. The stage stays, because the design and brief name it and
it states the intent; but this test shows "an old store opens", not "the
stage is what makes it open". I did not keep that *probe* (a temporary change
made only to find this out) in the code.

### Tests

- `SwiftDataRepositoriesTests`: a Book's Reading Mode is saved and read back
  unchanged (Vertical, then back to Page by Page); a stored Reading Mode that
  names no case reads as Page by Page; the V1 store opens in V2 (above).
- `LibraryModelTests`: choosing a Reading Mode when the Book's save fails
  queues no Notice and leaves the stored mode unchanged. It uses the same
  failing stand-in storage as the `turnPage` failure test. The existing
  failure-Notice table's `switch` gained `.chooseReadingMode` beside the other
  log-only operations (it would not compile otherwise).

### What Was Discovered

- Before the code existed the test target failed to compile (no `readingMode`
  on the stored Book, no `FolioSchemaV1.BookModel`, no `makeContainer(at:)`).
- The test run's log shows the failure path end to end: the Library throws
  `storage(.chooseReadingMode)` and logs "Could not Choose Reading Mode" under
  `AppLog.library`; the model then logs "Could not save the Reading Mode" under
  `AppLog.library` and queues nothing.

### Gate

- `./scripts/test.sh` (FolioCore 90 tests, then iOS and macOS app tests):
  every part succeeded.
- `./scripts/format.sh --check`: clean.

### Not checked

- The migration was checked with a store file written by the frozen V1 shape
  in a test, not with a store written by a build of the app that shipped V1.
- The Mac and iOS apps were not launched for this task (nothing visible
  changes yet: no screen calls `chooseReadingMode`).

## Task 3: Pure pieces for Vertical

Terms for this section. A *slice* is one horizontal band of a decoded Page, at
most 2,048 pixels tall; Vertical will show a Page as its slices laid edge to
edge, so no single picture handed to the screen is taller than the graphics
hardware can take. A *budget* is a limit in bytes of memory: the *per-Page
budget* is the most one decoded Page may take (96 MB on iPhone and iPad, 256 MB
on Mac), and the *cache budget* is the most all the decoded Pages kept at once
may take (three Pages' worth by default). *Released* means the app lets go of a
Page's decoded slices to free the memory; the Page is decoded again if the
reader scrolls back to it. A *pixel size* is a Page's width and height in
pixels. A *prefetch* is decoding the Pages near the one being read before the
reader reaches them. The *cache* is the part of the app that holds decoded
Pages in memory, so a Page is not decoded again every time it is shown.
`footprint` is Apple's command-line tool that reports the memory the system
counts against an app. None of this is on screen yet: Task 4 builds the
Vertical strip on top of these pieces.

### What Changed

- `Reading/StripGeometry.swift` (new): from every Page's pixel size and the
  strip's width, works out each Page's height, where each Page starts and the
  strip's total height, before any Page is decoded (a Page whose size is
  unknown, or has no area, takes a square). It also answers "which Page is at
  the top of the screen" with the design's rule: the last Page that has reached
  the top; the last Page once the strip is scrolled to the very end; the first
  Page when the strip has not been scrolled (so a strip shorter than the screen
  stays on its first Page). Ruling 2 fixed the test numbers.
- `Reading/PageImage.swift`: `pixelSize(url:)` reads a Page's width and height
  without decoding it, and swaps them for a Page stored on its side.
  It gives nothing for a Page whose stored data is not a picture.
- `Reading/SlicedPage.swift` (new): the width rule (the smaller of the Page's
  own width and the screen's, lowered until width x height x 4 bytes fits the
  per-Page budget, never below 1), the decode, and the byte count of a set of
  slices.
- `Reading/SlicedPageCache.swift` (new): keeps the slices of the Pages read so
  far, decodes one at a time, and after every Page it decodes releases the
  least recently used Pages while the total is over the cache budget, never the
  Page at the top of the screen, the one after it, or the Page it is handing
  back. (Fix round 1, below, changed this from "once, after a whole prefetch".)
- Tests: `StripGeometryTests`, `SlicedPageTests`, `SlicedPageCacheTests`, and
  two new tests in `PageImageTests`. `PNGFixture` (in `SlicedPageTests.swift`)
  writes the small test Pages.

### How a Page is decoded, and why slices are redrawn

`SlicedPage.decode` asks the system's image reader (ImageIO) for the Page at
the chosen width, then copies each band of rows into a new, independent picture
of its own. The whole decoded Page is held only inside `decode`, so it is let
go as soon as `decode` returns and only the slices survive. Copying is
deliberate: the cheaper way, cropping, hands back a picture that Apple documents
as keeping the whole picture it was cut from alive (quoted below), which would
have kept every Page's whole decoded picture in memory behind its slices and
made the byte count wrong. Each band is drawn into a drawing surface of its own
and taken out with `CGContext.makeImage()`, which Apple documents as a copy
(quoted below), so a slice depends neither on that surface nor on the whole
Page.
`SlicedPage.bytes(of:)` adds up rows times bytes per row of the slices actually
held.

### Apple documentation relied on

Fetched from `developer.apple.com/tutorials/data/documentation/<path>.json` on
2026-11-09.

- `kCGImageSourceThumbnailMaxPixelSize` (`imageio/kcgimagesourcethumbnailmaxpixelsize`):
  "The maximum width and height of a thumbnail image, specified in pixels." and
  "If this key is not specified, the width and height of a thumbnail is not
  limited and thumbnails may be as big as the image itself."
- `kCGImageSourceCreateThumbnailFromImageAlways`
  (`imageio/kcgimagesourcecreatethumbnailfromimagealways`): "A Boolean value that
  indicates whether to always create a thumbnail image." and "...the image
  source creates the thumbnail from the full image, subject to the limit
  specified by [kCGImageSourceThumbnailMaxPixelSize]. If you don't specify a
  maximum pixel size, the image source creates the thumbnail using the image's
  full size, which in most cases is not desirable."
- `kCGImageSourceCreateThumbnailWithTransform`
  (`imageio/kcgimagesourcecreatethumbnailwithtransform`): "A Boolean value that
  indicates whether to rotate and scale the thumbnail image to match the
  image's orientation and aspect ratio."
- `CGImage.cropping(to:)` (`coregraphics/cgimage/cropping(to:)`): "Creates a
  bitmap image using the data contained within a subregion of an existing bitmap
  image." and "The resulting image retains a reference to the original image,
  which means you may release the original image after calling this function."
  This is why the slices are redrawn into their own pictures instead.
- `CGContext.makeImage()` (`coregraphics/cgcontext/makeimage()`, fetched during
  the review of this task): "Creates and returns a CGImage from the pixel data
  in a bitmap graphics context." and "The CGImage object returned by this
  function is created by a copy operation. Subsequent changes to the bitmap
  graphics context do not affect the contents of the returned image. In some
  cases the copy operation actually follows copy-on-write semantics, so that the
  actual physical copy of the bits occur only if the underlying data in the
  bitmap graphics context is modified." Each slice relies on this: its pixels
  are its own, and the drawing surface is let go once the slice is taken out,
  so nothing draws into it again.
- `CGImageSourceCopyPropertiesAtIndex` (`imageio/cgimagesourcecopypropertiesatindex(_:_:_:)`):
  "Returns the properties of the image at a specified location in an image
  source." `kCGImagePropertyPixelWidth`: "The number of pixels along the x-axis
  of the image." `kCGImagePropertyOrientation`: "The intended display
  orientation of the image." and "The value encodes the intended display
  orientation for the image according to the TIFF and EXIF specifications."
- `CGImagePropertyOrientation` (`imageio/cgimagepropertyorientation` and its
  cases): `left`: "The encoded image data is rotated 90° clockwise from the
  image's intended display orientation."; `right`: "...rotated 90°
  counter-clockwise..."; `leftMirrored` and `rightMirrored`: flipped and rotated
  90°. The code swaps width and height for exactly these four cases and does not
  use the numbers 5 to 8 (Apple's pages do not print the numbers).

### What the documentation does not say (observed)

- Whether the pixel width and height ImageIO reports are before or after the
  orientation. Observed: for a JPEG written with orientation `right`, they are
  the stored (unrotated) size, so the code swaps them. The test
  `pixelSizeAppliesOrientation` checks this, on both platforms.
- Whether the decoded width comes out exactly as asked when only the longer
  side is limited. Observed in every case measured below: the decoded width
  equals the requested width, and the height equals the requested longer side
  (the Page's height at that width, rounded up).
- Whether ImageIO decodes the whole Page at once. Observed (macOS, a
  1,179 x 15,720 Page, through `footprint`): the whole decoded Page was not held
  in memory in full beside the slices; memory while slicing was about the
  slices' own 71 MB plus the app's 5 MB, not double. Not documented, so this is
  not relied on for correctness. Nor do the budgets cover the other case: while
  a Page is being cut into slices, its whole decoded picture and its slices can
  both be in memory, up to about twice the per-Page budget for that moment, and
  nothing counts it.
- How much memory slices that are held but not being drawn cost. Observed
  (macOS, same Page): `footprint` reported about 6 MB for the process while the
  eight slices were held and untouched, and 77 MB again once every slice's bytes
  were read. So the 71 MB is the cost of slices in use; the budget counts that
  full cost, which is the safe side. This measurement also could not tell the
  redrawn slices from cropped ones, so the choice to redraw rests on Apple's
  sentence above, not on the measurement.

### Measured decoded sizes

Measured with a throwaway test (not committed) that wrote each Page as a PNG,
asked `decodeWidth` for the width and ran `decode`. Sizes are `bytes(of:)`, rows
times bytes per row, so they include the few bytes of padding at the end of each
row. Times are on this Mac.

| Page (pixels) | Device case | Decoded at | Slices | Decoded size | Time |
| --- | --- | --- | --- | --- | --- |
| 800 x 12,000 | iPhone (screen 1,179 wide, 96 MB budget) | 800 x 12,000 | 6 | 38,400,000 bytes (36.6 MB) | 0.03 s |
| 800 x 12,000 | Mac (screen 2,880 wide, 256 MB budget) | 800 x 12,000 | 6 | 38,400,000 bytes (36.6 MB) | 0.03 s |
| 3,000 x 40,000 | iPhone (screen 1,179 wide, 96 MB budget) | 1,179 x 15,720 | 8 | 74,449,920 bytes (71.0 MB) | 0.19 s |
| 3,000 x 40,000 | Mac (screen 2,880 wide, 256 MB budget) | 2,243 x 29,907 | 15 | 268,923,744 bytes (256.5 MB) | 0.43 s |

The last row is 0.2% over the 256 MB per-Page budget. The width rule counts
width x height x 4 bytes, as the plan says, but the system pads each row (8,992
bytes per row for 2,243 pixels, not 8,972), and the padding is what pushes it
over. The size of the padding is not documented, so the rule was not changed to
guess it. The cache budget is checked against the real byte count, so the cache
itself is not misled.

### Tests

- `StripGeometryTests`: heights and tops for the brief's three Pages; a size
  with no area is a square; the Page at the top for the eight offsets of
  ruling 2; a strip shorter than the screen stays on its first Page until it is
  scrolled; one Page and an empty strip.
- `PageImageTests`: `pixelSize` of a 64 x 96 PNG is 64 x 96, of a text file and
  a missing file is nothing; a JPEG stored on its side reports its width and
  height swapped.
- `SlicedPageTests`: the width rule (a narrow Page keeps its width; a wide one
  takes the screen's width; a Page too tall for the budget is lowered to the
  widest width that fits, and one pixel wider would not fit; never below 1 and
  never above the Page's own width); a 64 x 5,000 Page decodes to slices of
  2,048, 2,048 and 904 rows, all 64 wide; a narrower decode scales the whole
  Page; the slices keep the rows in order (red top, blue bottom); an
  undecodable or missing file gives nothing.
- `SlicedPageCacheTests` (ruling 3): the budgets are set from the measured size
  of one decoded 8 x 8 Page, so exactly two Pages fit and a third does not. A
  Page is decoded once and reused; with Page 0 retained, prefetching around 0
  keeps Pages 0 and 1 and releases Page 2 (asking for it again decodes it
  again); `retain` releases the least recently used Page first; a Page that
  cannot be decoded is remembered and not retried; a request from a cancelled
  task decodes nothing; an index outside the Book gives nothing.

### What Was Discovered

- Before the code existed the test target failed to compile (22 errors: no
  `StripGeometry`, `SlicedPage`, `SlicedPageCache` or `pixelSize`).
- Both important tests were shown to be able to fail. With the release line in
  the cache replaced by a no-op, `budgetReleasesTheOldestOthers` and
  `retainReleasesOldest` fail (the second `decodeCount == 4` expectations).
  With the slices made by cropping instead of redrawing,
  `slicesKeepRowOrder` fails. Both edits were reverted.
- The brief's width test could not be written as given: for a 3,000 x 40,000 Page
  on a 1,179-wide screen with the 96 MB budget, 1,179 pixels wide takes
  74,449,920 bytes (71.0 MB, counting a MB as 1,048,576 bytes as the budgets
  do), which fits, so "one pixel wider would not fit" is false there. The
  test was split in two: at 96 MB the width is the screen's 1,179; with a 32 MB
  budget it is lowered, and one pixel wider no longer fits.
- A test I first wrote to show that slices own their pixels (the length of each
  slice's data equals its rows times bytes per row) passed for cropped slices
  as well, so it proved nothing and was removed.
- A freshly decoded Page is read lazily and slices may cost little while
  untouched (see "observed" above); the budgets and the byte count deliberately
  ignore that.

### Fix round 1: the cache trims after every decode

The first version trimmed the cache only when the reader's top Page changed and
once at the end of a prefetch. A prefetch decodes up to four Pages, so after a
jump (the slider, a Page-to-Page switch) the cache briefly held the Pages that
were already there plus four new ones: about seven Pages' worth of slices
instead of the three the design allows, roughly 672 MB on an iPhone and 1.8 GB
on a Mac against a stated limit of 288 MB and 768 MB. The design says memory
stays within the stated budget however tall the Pages are, and that binding
sentence wins over the plan's wording ("decodes ... then applies the budget").

What changed, in plain terms:

- The cache now trims after every single Page it decodes. It never lets go of
  the Page at the top of the screen, the one after it, or the Page it is just
  about to hand back; anything else goes, least recently used first. At any
  moment after a call returns, the cache holds at most its budget plus the one
  Page just returned. At the end of a prefetch it holds only the top Page and
  the next.
- A prefetch now decodes the Page the reader is on first, then the next two,
  then the one before, so the Page being read is ready soonest and a tall Page
  is not decoded for a neighbour before the one on screen.
- What a reader may notice: a Page just outside the kept pair can now be
  released sooner than before, so scrolling back to it a moment later may show
  a blank space of the Page's size briefly while it is decoded again (corrected
  in Task 5: the strip shows the placeholder only for a Page that cannot be
  decoded at all). In return, memory stays
  inside the stated limit.
- To let a test see this, the cache has a read-only `heldBytes` (the bytes of
  the slices it holds now).

The new test, `budgetHoldsAfterEveryDecode`, jumps from Page 0 to Page 5 in a
nine-Page Book with a budget of two Pages, asks for the Pages a prefetch would
ask for one at a time, and checks after each that the cache holds no more than
its budget plus one Page; it then checks that a whole prefetch ends holding
exactly the top Page and the next. It failed against the first version (three
expectations, one per extra Page held) and passes now. The order of the prefetch
is not covered by a test of its own.

### Gate

- `./scripts/test.sh macos` (iterating): succeeded.
- `./scripts/test.sh` (iOS and macOS app tests): both succeeded.
- `./scripts/format.sh --check`: clean.

### Not checked

- The iOS device case is the measured iPhone-sized row run on the Mac; I did not
  measure decoded memory on an iPhone or the iOS simulator, and the 96 MB figure
  is not tuned from a device. Peak memory while a Page is being decoded was only
  observed on macOS.
- Nothing calls these pieces yet, so the strip, the Reading Position's Page at
  the top and scrolling were not run; Task 4 does that.

## Task 4: The Vertical strip on screen, the Reading Mode control, strings

The terms below are used in this section.

- **The strip** is the Vertical screen: every Page at the screen's width, one under the other with no gap, in one scroll view.
- **The Page at the top** is the Page being read, by the top-of-the-screen rule from Task 3.
- **A jump** is code moving the strip so a Page's top is at the top of the screen. It happens when the Book opens, when the Reading Mode is switched, and when the slider or a key picks a Page.
- **The scroll phase** is Apple's name for what a scroll view is doing at a given moment. Its values are:
  - idle: nothing is moving;
  - tracking: a finger is down but has not moved yet;
  - interacting: the reader is dragging;
  - decelerating: the reader has let go and the strip is coasting;
  - animating: code is scrolling with an animation.
- **A plain stack** works out where every row sits before anything is shown. **A lazy stack** works out a row's place only as that row comes near the screen. Apple says this trades "some degree of layout correctness for performance" (quoted below), and on the simulator rows far from the screen were not where their known heights put them (see "Why a plain stack").
- **The Pages kept decoded** are the Pages the strip asks the cache for at a given moment: every Page with any part on screen, plus one more on each side.
- **The pixel grid** is the screen's own dots. On the iPhone simulator, with 3 pixels per point, the scroll view was seen to come to rest only on whole pixels, which are thirds of a point. This is observed on the simulator; Apple does not document it (see "What the documentation does not say").

### What Changed

- **`Reading/VerticalStripView.swift` (new): the strip.**
  - It is a scroll view that moves down, and sideways only when zoomed. Inside it is a plain stack of rows, one per Page. Each row is exactly as tall as the Page's pixel size gives at the screen's width; a Page that is not a picture is a square.
  - A row among the Pages kept decoded shows that Page's slices from the cache, nothing while they are being decoded, or the placeholder if the Page cannot be decoded. Any other row shows nothing and does not ask the cache.
  - The strip keeps its own cache of slices. It is rebuilt when the screen's width in pixels changes, and it is told the Page at the top so its budget never lets go of that Page or the next.
  - Zoom uses the same gestures and limits as a single Page: a pinch up to 5 times; a double tap to 2.5 times and again back to fit; a pinch to zoom out stops at fit, so the strip is never narrower than the screen. (The design says letting go below fit snaps back; as on a single Page, the code holds the zoom at fit during the pinch, so there is nothing to snap back.) It zooms the whole strip, and the reader will notice three differences from a single Page:
    - zooming, and any other change of the screen's width, keeps the reader at the same place inside the Page under the top of the screen (fix round 1);
    - a double tap zooms at once, without the animation a single Page uses (fix round 2);
    - on every zoom step the strip is centred across, so a reader who had panned sideways is put back in the horizontal middle.
- **`Reading/StripGeometry.swift`:**
  - `pagesToDecode(offset:viewportHeight:)` gives the Pages kept decoded for a scroll position.
  - `offset(keepingPlaceOf:in:)` gives, for a new width or zoom, the position that keeps the reader the same fraction of the way down the Page under the top of the screen.
  - Every Page's height is now rounded to the screen's pixel grid; the screen is asked how many pixels it has per point rather than a number being assumed (fix round 1).
- **`Reading/ReadingView.swift`:**
  - The screen holds the Reading Mode, starting from the Book's own (`startMode(for:)`), and shows the pager or the strip accordingly. A switch makes SwiftUI treat the content as a new view (it gets a new identity), which resets zoom.
  - Choosing a mode changes the screen at once and asks the model to save the choice afterwards. A failed save stays log-only, in the model (Task 2).
  - The Page by Page cache starts empty after each switch and prefetches only in Page by Page, so the two modes never hold decoded Pages at the same time.
  - Pixel sizes are read once per Book, in the background so the screen does not freeze, the first time the Book is shown Vertical. Until they are read the screen is blank, with the chrome as usual (ruling 11).
  - On Mac the left and right arrow keys still turn Pages in both modes. In Vertical the turn is a jump without animation.
- **`Reading/PageView.swift`:** the maximum zoom and the placeholder are shared with the strip. Page by Page behaves as before.
- **The Reading Mode control**, shown with the chrome:
  - on Mac, a segmented control in the toolbar with "Page by Page" and "Vertical";
  - on iPhone and iPad, a button in the navigation bar (the `book.pages` symbol, labelled "Reading Mode") that opens a menu with the two modes, the current one ticked. Two labelled segments beside the Title and Close would crowd the iPhone's bar.
- **`Localizable.xcstrings`:** "Reading Mode", "Page by Page", "Vertical". The catalog was synced from both platforms' compiled string lists and the compact `{}` entries restored, so the diff shows only these three keys. "Reading Mode" is also the control's accessibility label, so no other string was needed.

### How the strip knows which Page you are on

Each time the strip moves, the scroll view reports two numbers: how far the strip is scrolled, measured from the top of the first Page, and how tall the visible area is. From these:

1. **The Pages kept decoded are worked out on every report.**
2. **The Page at the top is worked out on every report, but it becomes the Page being read only while the scroll phase says the reader is moving the strip**: interacting or decelerating (ruling 10 as amended by ruling 13). Tracking, a finger down that has not moved, does not count, so a tap never changes the Page. Every Page the reader scrolls onto is saved once, through the model's `turnPage`, as with a swipe in Page by Page.

   The opening, a switch, the slider and the keys set the Page being read directly. The scroll view's own reports while it is being put in place never change it. This is what stopped a Book from opening on Page 1: the scroll view reports the top of the strip once, before the jump, and that report used to overwrite the Reading Position.

   One consequence the reader can see (added in Task 5): after a jump to a Page near the end whose top cannot reach the top of the screen, because the strip stops at its bottom first, the counter and the Reading Position stay on the Page asked for, while the end-of-strip part of the top-of-the-screen rule would say the last Page. For example, in the 12-Page Book of fix round 1, the slider to Page 11 leaves the strip at its very end, with the bottom of Page 10 and all of Pages 11 and 12 on screen, and the counter reads "Page 11 of 12". As soon as the reader scrolls, the rule applies again. Reopening a Book whose Reading Position is its last Page still lands exactly at the bottom (seen on the simulator).
3. **When the reader starts or stops moving the strip, the phase change also carries the strip's position**, so the Page they stop on is never missed.
4. **When the Page being read changes and that Page is not already the Page at the top, the strip jumps there.**

   The "not already at the top" part is the one check the brief asked for, and it is still needed. Every Page the reader scrolls onto comes back to the strip as a change of the Page being read. Without the check, the strip would then pull that Page's top up to the top of the screen while the reader is still scrolling.

   It used to compare with "the Page the rule last reported". It now compares with the Page at the top at the last report, because the old form could go stale after a slider jump and then skip a later jump.
5. **When the screen's width or the zoom changes, every Page's height changes.** The strip then moves to the same place inside the Page under the top of the screen: the same fraction of the way down that Page (fix round 1). The Page being read does not change.

   Across, the strip is centred on every zoom step. A reader who had panned sideways to a corner of the Page is put back in the horizontal middle each time they pinch or double tap.

### Why a plain stack (ruling 12)

With the plan's lazy stack, on the iPhone simulator, after a slider drag to the end of a 24-Page Book:

- the scroll view reported positions up to 24,671 points in a strip that is 20,770 points tall;
- swiping back showed Page 20 at the top while the counter read "Page 24 of 24";
- a jump to Page 21 landed at the end instead of at Page 21's top.

Apple documents why, in the quotes under "Apple documentation relied on" below: a lazy stack works out a row's place only as it nears the screen, while a plain stack knows every row's size.

With the plain stack the same checks pass: the positions match the known Page heights exactly. The cost is that every row (the space kept on screen for one Page) exists at once, empty until its Page is decoded; for a 1,000-Page Book that is 1,000 rows. Because a plain stack creates every row at once, decoding cannot start "when a row appears". The Pages kept decoded decide it instead.

### Apple documentation relied on

All fetched on 2026-11-09 from `developer.apple.com/tutorials/data/documentation/swiftui/<path>.json`.

- **Creating performant scrollable stacks** (`creating-performant-scrollable-stacks`):
  - "Stack views load their child views all at once, making layout fast and reliable, because the system knows the size and shape of every subview as it loads them. Lazy stacks trade some degree of layout correctness for performance, because the system only calculates the geometry for subviews as they become visible."
  - "When choosing the type of stack view to use, always start with a standard stack view and only switch to a lazy stack if profiling your code shows a worthwhile performance improvement."
  - "Never profile your code using the iOS simulator. Always use real devices for performance testing."
- **`onScrollGeometryChange(for:of:action:)`** (`view/onscrollgeometrychange(for:of:action:)`):
  - "Adds an action to be performed when a value, created from a scroll geometry, changes."
  - The action "is called whenever the data type changes".
  - "If multiple scroll views are found within the view hierarchy, only the first one will invoke the closure you provide". The strip has one scroll view.
- **`ScrollGeometry`:**
  - `contentOffset`: "This is the position of the scroll view within its overall content size. This value may extend before zero or beyond the content size when the content insets of the scroll view are non-zero or when rubber banding."
  - `contentInsets`: "Adding these insets to the content size of the scroll view will give you the total scrollable space of the scroll view."
  - `visibleRect`: "This value is computed from the scroll view's content offset, content insets, and its container size."

  The strip measures from the top of the first Page as offset plus top inset (ruling 6). The viewport height is the visible rectangle's height.
- **`onScrollPhaseChange(_:)`** (`view/onscrollphasechange(_:)-1k12m`):
  - "Adds an action to perform when the scroll phase of the first scroll view in the hierarchy changes."
  - "The system can also provide you with a context containing the geometry of the scroll view at the time of the phase change. You can use the geometry to understand where the scroll view has come or gone between the phase changes and update dependent state on that information."
- **`ScrollPhase`** (`scrollphase` and its cases):
  - `idle`: "The idle phase where no kind of scrolling is occurring."
  - `tracking`: "The tracking phase where the scroll view is tracking a potential scroll by the user but the user hasn't started a scroll." Also: "For example, on iOS, the user may start touching content inside of the scroll view. Until the user moves their finger the scroll view would be tracking the finger. Not all platforms or kinds of scroll may trigger this phase."
  - `interacting`: "The interacting phase where the user is interacting with the scroll view."
  - `decelerating`: "The decelerating phase where the user use has stopped interacting with the scroll view and the scroll view is decelerating towards its final target."
  - `animating`: "The animating phase where the scroll view is animating towards a final target." Also: "This phase is the result of a programmatic scroll when using a ScrollViewReader or scrollPosition(id:anchor:) modifier."

  Only `interacting` and `decelerating` count as the reader:
  - `tracking` is, in Apple's words, when "the user hasn't started a scroll", so a tap or a finger resting on the screen is not scrolling;
  - Apple ties `animating` to programmatic scrolls.

  Apple's text says nothing about which Mac input (wheel, trackpad, Page Up and Page Down, the arrow keys) gives which phase.
- **`ScrollPosition.scrollTo(x:y:)`** ("Scrolls the position of the scroll view to the x and y value you provide." and "The scroll view will clamp this value to only scroll to the size of its actual content.") with **`scrollPosition(_:anchor:)`** ("Use this modifier to control where a scroll view is positioned. You can use the ScrollPosition type to scroll in a variety of ways: ... scroll to a concrete offset"). This is how the strip keeps the reader's place after a zoom. Jumps to a Page still use `scrollTo(_:anchor:)`.
- **`ScrollViewProxy.scrollTo(_:anchor:)`:**
  - "Scans all scroll views contained by the proxy for the first with a child view with identifier `id`, and then scrolls to that view."
  - "setting `anchor` to top aligns the top of the identified view to the top of the scroll view."
  - `ScrollViewReader`: actions such as "a view's onChange(of:perform:) method" may call the proxy.
- **`scrollTargetLayout(isEnabled:)`:** "This modifier works together with the ViewAlignedScrollTargetBehavior to ensure that scroll views align to view based content." Neither the `scrollTo(_:anchor:)` page nor the `ScrollViewReader` page mentions it, and the strip uses neither view alignment nor `scrollPosition`, so it was left out.
- **`onChange(of:initial:_:)`:** `initial` means "Whether the action should be run when this view initially appears". This is how the strip makes its first jump to the Reading Position's Page.
- **`id(_:)`:** "When the proxy value specified by the `id` parameter changes, the identity of the view — for example, its state — is reset." This is how a switch resets zoom.
- **`scrollBounceBehavior(_:axes:)` and `basedOnSize`:** "The scrollable view bounces along the specified axis if the size of the content exceeeds the size of the scrollable view in that axis." At fit the strip is exactly as wide as the screen, so it does not move sideways.
- **`task(id:...)`:** "If the `id` value changes, SwiftUI cancels and restarts the task." This is how the cache is told the new Page at the top.
- **`Image(decorative:scale:orientation:)`:** "SwiftUI ignores this image for accessibility purposes." Each slice is decorative, and the whole Page carries the "Page n of m" label.
- **`MagnifyGesture`:** "A gesture that recognizes a magnification motion and tracks the amount of magnification." Used the same way as on a single Page.
- **Pickers.** `PickerStyle.segmented`: "Use this style when there are two to five options." `PickerStyle.menu`: "Use this style when there are more than five options."

  The iPhone control is a menu button holding the two options, not a menu-style picker. The HIG for segmented controls on macOS: "Consider using a segmented control to help people switch views in a toolbar or inspector pane."
- **Swift `Task.detached`** was not used. The pixel-size read is a `@concurrent` function (one Swift runs away from the screen's own thread), as `CoverView` already does.

### What the documentation does not say (observed)

All on the iPhone 17 Pro simulator, iOS 26.5, driven by an automation tool that sends taps and swipes to the simulator only. Numbers come from throwaway logging, removed before commit.

- **The scroll view reports its position once when the strip first appears**, with the old and new values equal (top of the strip, before any jump). Apple only says the action runs when the value changes. The scroll-phase gate is what keeps this report from changing the Reading Position.
- **Phases seen:**
  - a finger swipe goes idle → interacting → decelerating → idle;
  - jumps from the slider and on opening made no phase change (idle throughout);
  - a pinch made no phase change either;
  - one change arrives once with old and new both idle, at first appearance;
  - "decelerating → decelerating" also arrives.
- **With the strip under the whole screen (ignoring the *safe area*, the margins kept clear of the camera and the home bar), the top and bottom *insets* (space the scroll view adds above and below its content) were 0**, so the visible rectangle's height (874 points) is the visible area.
- **Jumps land on the Page's top to within the screen's pixel grid.** The scroll view stops on thirds of a point: Page 9's top is 12,629.5 and the strip stopped at 12,629.667. Because only the reader's scrolling changes the Page being read, this rounding cannot move the counter.
- **A strip shorter than the screen is centred vertically.** The one-Page Book's Page sits 135 points down. Nothing in the spec asks otherwise, so nothing was added.
- **Double tap and pinch now behave alike.** Both keep the reader's place vertically and centre the strip across.
  - Until fix round 2 the double tap zoomed with an animation. It then landed at the left edge across, and deep in the strip it landed on the wrong Page or a blank screen.
  - Since fix round 2 the double tap zooms at once, and the observed result is centred, like a pinch.

### Simulator checks

All on the iPhone 17 Pro simulator, iOS 26.5. The test Books were made outside the repository from generated pictures:

- **Strip Mixed**, 24 Pages: 800 x 4,000 and 600 x 12,000 Pages, wide Pages, and Page 5, which holds text, not a picture, though it is named like one.
- **Strip Short**, 12 Pages of 1,600 x 900, all shorter than the screen.
- **Strip One**, 1 Page.
- **Strip Thousand**, 1,000 Pages of 120 x 180 and 180 x 120.

| Check | Result |
|---|---|
| Switch to Vertical while on Page 4 | Page 4 at the top; counter "Page 4 of 24"; Reading Position stays Page 4 |
| Scroll, close, reopen | Library card read "Page 5 of 24"; reopening put Page 5's top at the top |
| Swiping | Counter followed the Page at the top; one save per Page crossed (Pages 5, 6, 7) |
| Slider jumps | Each landed with the Page's top at the top (Pages 9, 10, 11, 21; Page 993 of 1,000) |
| Slider to the end, then swipe back | Counter read "Page 20 of 24" with Page 20 at the top |
| Reopen a Book saved at Page 24 | Strip ended exactly at its bottom (scrolled to 19,896 + 874 = 20,770) |
| First appearance | Never changed the Reading Position, in any check above |
| Switch back to Page by Page from Page 7 | Page by Page showed Page 7 |
| Pinch | Zoomed about the top centre; panned sideways; no save during the pinch (see fix round 1 for the place inside the Page) |
| Double tap | Zoomed in (2.5x) and back to fit; deep in the strip see fix round 2 |
| Switching after a zoom | Strip came back at fit |
| All Pages shorter than the screen | Switching on Page 5 and reopening both put Page 5 at the top; counter "Page 5 of 12" |
| One-Page Book | Slider disabled; Page 1 at every position, including when pulled past either end |
| Page that is not a picture (Page 5, which holds text) | Square of the screen's width with the placeholder; reaching it did not move the strip |

### Measured (simulator on this Mac, not a device)

| What | Book | Result |
| --- | --- | --- |
| Reading every Page's pixel size | 24 Pages (Strip Mixed) | 0.010 to 0.022 s |
| Reading every Page's pixel size | 1,000 Pages | 0.153 s on the first open; 0.060 to 0.219 s on later opens |
| From the sizes being read to the strip first being placed on screen | 1,000 Pages | 17 to 20 ms |
| Rows asking the cache after opening | 1,000 Pages, at Page 1 | 3 |
| Rows asking the cache after opening | 24 Pages, saved at Page 24 | 7 (see below) |
| Rows asking the cache during a long fast scroll | 1,000 Pages, Page 1 to 428 | 416 asks over the scroll; at most 6 at once, 5 at rest; 419 decodes in all |
| Reading Position saves during that scroll | as above | 218 for 427 Pages crossed |
| Slices held by the cache | Strip Mixed, plain stack | at most 50,720,000 bytes (48.4 MB; the iPhone cache budget is 288 MB) |
| Memory used by the app (`footprint`) | 1,000 Pages, after the long scroll | 67 MB |

Notes on the table:

- **The 24-Page open.** 3 of the 7 rows asked because of the first report at the top of the strip, before the jump. Two of them were cancelled before decoding; one (about 2.9 million bytes) decoded for nothing.
- **Saves during the fast scroll.** One report can cross several Pages, so a save is made at most once per Page crossed, never more.
- **The real Sample Book** (`~/Downloads/FolioSamples/Sample Book`) has 3 Pages, so the 24-Page figure is for Strip Mixed.
- **The 1,000-Page read is under 0.3 s** on the simulator.

### Tests

- **`StripGeometryTests`** (`pagesToDecode`):
  - a Page partly on screen counts;
  - one Page more on each side, clamped at the first and last Page;
  - scrolled past either end keeps the nearest Page and its neighbour;
  - Pages shorter than the screen keep more Pages than one tall Page does;
  - one Page always, and an empty strip none.
- **`ReadingViewTests`:**
  - `startMode` is the Book's own Reading Mode;
  - the strip's scroll is measured from the top of the content under an inset;
  - only interacting and decelerating count as the reader; idle, tracking and animating do not (fix round 1).

### What Was Discovered

- **Before the code existed, the new tests failed to compile:**
  - for `startMode` and `StripScroll`: "type 'ReadingView' has no member 'startMode'" and "cannot find 'StripScroll' in scope";
  - for the decode window: "value of type 'StripGeometry' has no member 'pagesToDecode'".
- **Starting a Page's decode when its row appears could not stay within the budget in a plain stack**, where every row appears at once. With Apple's on-screen visibility check at threshold 0, all 24 rows of Strip Mixed reported visible. This was tried and dropped for the pure function above (ruling 12).
- **Asking SwiftUI to open the scroll view at a Page by name** (`ScrollPosition` with a starting id) did not stop the first report at the top of the strip either. Tried, reverted.
- **An existing warning in the reading screen's code is not turned into an error by the build:** `ReadingView.swift:95`, "main actor-isolated property 'displayScale' can not be referenced from a Sendable closure", in the Page by Page size observer, which was there before this task. Tests that call main-actor helpers (`startIndex`, `LibraryWindow.push`) warn the same way. The settings say warnings are errors, but the build passes. It is reported, not silenced.

### Gate

- `swift test --package-path app/FolioCore -Xswiftc -warnings-as-errors`, through `verify.sh`.
- `SIMULATOR=F9304E8C-40F4-4962-A836-C10615C7DC16 SKIP_LAUNCH=1 ./scripts/verify.sh`: format, build and test for iOS and macOS.
- The launch step was skipped because on macOS it takes a picture of the whole desktop, which is the project owner's screen. The launches were done separately: `./scripts/run.sh ios --screenshot` on the simulator, and `./scripts/run.sh macos` without the screenshot. Neither sends any input.
- `./scripts/format.sh --check`: clean.
- The vocabulary check (`grep` for the words to avoid in `app/Folio/Reading` and `app/FolioTests`) shows only `.scrollTargetLayout()`, the Apple name in the existing pager.

### Not checked

- **Everything on the Mac.** After an early attempt in this task sent keystrokes to the owner's Mac (they landed in another window), agents send no input to the Mac at all. These are on the owner's list:
  - the segmented control in the toolbar;
  - Vertical scrolling with the wheel and the trackpad;
  - left and right arrows turning Pages in both modes;
  - does the counter follow Page Up, Page Down and the up and down arrows in Vertical? Apple does not say which phase keyboard scrolling reports. If it is not one of the reader's phases, the counter would stay put while the keys scroll.
  - window resizing keeping the reader's place inside the Page;
  - Escape closing the Book.
- **iPad and iPhone rotation.** Not run. The simulator tools available here cannot turn the device, and turning it from the Simulator app's menu would be input to the Mac.

  Turning the device is an animated change of the strip's width. The limit that broke the animated double tap (fix round 2) may affect it too: a reader deep in the strip might land on the wrong Page after turning the device. This is unchecked and on the owner's list.
- **Performance on a device.** Apple says to profile on a real device, not the simulator; every number above is from the simulator. Open question for the owner: is a plain stack of 1,000 or more rows smooth enough on a real iPhone?
- **The HIG for macOS toolbars** says "Make every toolbar item available as a command in the menu bar". There is no Reading Mode menu command; it is outside this task's brief.

### Fix round 1: only the reader's scrolling counts, the place inside a Page is kept, Page heights sit on the pixel grid

Review found three defects. Rulings 13, 14 and 15 settled them.

**1. A tap could change the Reading Position (ruling 13).**

Defect: "tracking" counted as the reader moving the strip. Apple describes tracking as the moment "the user hasn't started a scroll".

Example: a Book reopened on Page 11 of 12 rests at the end of the strip, where the rule says Page 12. A tap there could have saved Page 12.

Change: only interacting and decelerating count now.

Seen on the simulator: with the counter on Page 11 at the end of the strip, four taps and a one-second press without moving left the counter on Page 11, and nothing was saved. Taps and presses showed no phase change at all on the simulator, so tracking itself was never seen there. The fix rests on Apple's text.

**2. Zooming inside a tall Page threw the reader back to the Page's top (ruling 14).**

Defect: every pinch step, rotation or window resize scrolled to the top of the Page being read. Zooming in the middle of a 600 x 12,000 Page was unusable.

Change: the strip now remembers where the last report put it, and in which geometry. When the width or zoom changes it moves, through `ScrollPosition.scrollTo(x:y:)`, to the same fraction of the way down the Page under the top of the screen in the new geometry, centred across. The fraction arithmetic is the pure `StripGeometry.offset(keepingPlaceOf:in:)`.

Seen on the simulator, at the 600 x 12,000 Page 7 (8,040 points tall at fit):

| Step | Top of the screen inside Page 7 |
|---|---|
| Before zooming | 2,731 points down (34%) |
| After a 2x pinch | 5,461 of 16,080 points (34%) |
| After pinching back | 2,731 points again |
| After a 2.5x double tap | 6,828 of 20,100 points (34%) |
| After double tap back to fit | 2,731 points |

Nothing was saved during these zooms.

What the reader will notice: zooming keeps the part of the Page they were looking at under the top of the screen. Fix round 2 found that this held for a pinch but not for a double tap deep in the strip, and corrected it.

Rotation: not checked (see Not checked).

**3. A jump could land just above a Page's top, and the next jump back was lost (ruling 15).**

Defect: Page heights were not on the pixel grid, so a Page's top could fall between pixels while the scroll view stops on whole pixels (observed on the simulator; Apple does not document it).

Reproduced first on the committed code, with a generated Book of twelve 1,000 x 1,001 Pages (402.402 points tall each):
1. The slider jump to Page 6 (top 2,012.010) stopped at 2,012.000.
2. The rule then read Page 5 at the top.
3. A slider step back to Page 5 was swallowed by the "already at the top" check. The counter read "Page 5 of 12" while Page 6 was at the top.

Change: `StripGeometry` now takes the display's pixels per point and rounds every Page's height to a whole number of screen pixels. Its tops and the strip's height are counted in whole pixels, so every top lies on the grid where the scroll view was seen to stop.

Seen on the simulator with the fix:
- the jump to Page 6 stopped at 2,011.667, exactly its top, and read Page 6;
- the step back to Page 5 jumped to 1,609.333, its top, and showed Page 5.

What the reader will notice: nothing, except that this mismatch no longer happens. Each Page is at most half a pixel taller or shorter than before.

**Tests**

- `StripGeometryTests.pixelGrid` (at 2 and 3 pixels per point): every height and top is on the grid; the first height is within half a pixel of the exact one; a Page that is not a picture is a square; tops, heights and the strip's height agree to the pixel; a top reads its own Page and one pixel above reads the Page before.
- `StripGeometryTests.keepingPlace`: zoom in; zoom out; the first Page; the last Page; past either end.
- `StripGeometryTests.keepingPlaceOnePageAndEmpty`: a one-Page strip and an empty strip.
- The Task 3 geometry tests now pass a display scale of 1. Their heights are whole numbers, so nothing else changed.
- `ReadingViewTests.readerScrolling`: tracking is not the reader.

Before the code: the new geometry tests failed to compile ("extra argument 'displayScale' in call"). With the geometry done but the phase rule not yet changed, the phase test failed for `tracking`.

**Gate**

- `./scripts/test.sh macos`: 118 tests passed.
- `SIMULATOR=F9304E8C-40F4-4962-A836-C10615C7DC16 SKIP_LAUNCH=1 ./scripts/verify.sh`: format, build and test for iOS and macOS, including FolioCore's 90 tests.
- `./scripts/format.sh --check`: clean.

### Fix round 2: a double tap zooms at once, so it keeps the reader's place deep in the strip

Review found that a double tap far down the strip landed on the wrong Page or a blank screen (ruling 16). Cases seen in Strip Mixed, whose strip is 20,771 points tall at fit:

- **At Page 21.** A double tap showed Page 7 filling the screen at 2.5x, while the counter still read Page 21.
- **At the end of the strip.** A double tap turned the screen black. A short drag then showed Page 7 and saved it as the Reading Position.

Cause, as far as it can be documented (Task 5 separated what is known from what is inferred):

- Known from the code: the double tap changed the zoom inside an animation, and the move that keeps the reader's place was asked for at once.
- Inferred, neither documented nor measured directly: during the animation the strip's new height took effect on screen gradually, so when the move was asked for, the content was still its unzoomed size.
- Apple's text for that move, `ScrollPosition.scrollTo(x:y:)`, is: "The scroll view will clamp this value to only scroll to the size of its actual content." If the inference holds, the move was cut short at the unzoomed strip's last position (about 19,897 points), which at 2.5x is in Page 7, the Page that was seen.
- A pinch changes the zoom in small steps without animation, and none of the pinches checked was cut short (observed). My own double-tap check in fix round 1 was made at 7,153 points; its target, 17,884, was under the unzoomed strip's last position, which fits the inference.

Change: the double tap now changes the zoom at once, without animation. No timer, delay or second move was added.

When SwiftUI runs the "zoom changed" action relative to laying out the new size is not something Apple documents. `onChange(of:initial:_:)` says only that the system "may call the action closure on the main actor". That the move lands correctly when the zoom is not animated is observed:

| Where | Before | After | Then |
|---|---|---|---|
| Page 21 at the top | Page 21 at fit | 2.5x: Page 21 still at the top, centred across | Back to fit: Page 21 at the top |
| End of the strip | Top of the screen 64 of 603 points into Page 22 (10.6%) | 2.5x: 160 of 1,507 (10.6%), the Page in view, not blank | Back to fit: the end of the strip again |
| 57.7% of the way down the 600 x 12,000 Page 7 | 4,640 of 8,040 points | 2.5x: 11,600 of 20,100 (57.7%) | Back to fit: 4,640 |

Pinches from the same places still pass:
- 2x at the end: 127 of 1,206 into Page 22 (10.5%);
- 2x at Page 7: 9,280 of 16,080 (57.7%);
- 2x at Page 20 (the slider stopped one Page short of 21), deep in the strip: Page 20 stays at the top;
- pinching back returned each to its fit position.

No zoom saved a Reading Position. Every save in the probe log (the temporary logging added for these checks) came from my own swipes and slider jumps, and none fell during a zoom. The Library cards afterwards read Page 20, Page 24 and Page 7, the Pages each Book was left on before zooming.

What the reader will notice:
- The double tap zooms instantly instead of with a short animation.
- Deep in the strip it keeps the part of the Page they were looking at, like a pinch.
- It now also lands centred across, where before it lined up with the left edge. That is observed, not something Apple documents.

Rotation is an animated size change too and could not be checked (see Not checked).

Tests: no unit test changed. The change only removes an animation, and the arithmetic it relies on (`StripGeometry.offset(keepingPlaceOf:in:)`) is already covered by `keepingPlace` and `keepingPlaceOnePageAndEmpty`.

Gate: `./scripts/test.sh macos`, then `SIMULATOR=F9304E8C-40F4-4962-A836-C10615C7DC16 SKIP_LAUNCH=1 ./scripts/verify.sh`, and `./scripts/format.sh` followed by `--check`.

## Task 5: Docs and the owner's check list

### What Changed

- `DECISIONS.md`: a "2026-11-09: Reading Mode" section in plain language. It holds the six entries the design asks for and the rulings that change what a reader experiences: only the reader's scrolling counts; sizes are read first; a plain stack; zoom keeps the place; heights on the pixel grid; the budget applied after every decode. It also says what is not yet verified.
- `CLAUDE.md`: the Reading paragraph names `VerticalStripView`, `SlicedPageCache`, `StripGeometry` and `SlicedPage` and says what each does; the Domain list names Reading Mode.
- `docs/logs/2026-11-09-01-reading-mode-design.md`: Status, Commits, and a paragraph on where the implementation differs from the design.
- This log: the summary, the owner's check list, the memory table, the rulings and the deferred items, and the commits. Also these corrections to the earlier sections:
  - **Context:** store, decoding, log-only, chrome, point and fit are defined.
  - **Task 1:** a Book is no longer described with the glossary's word to avoid for a Source; it is "the Book it was made from".
  - **Task 2:** SwiftData carrying the data across by itself is labelled observed. "Proof" is now "evidence". Stage, stage list, probe and frozen are defined where they are first used.
  - **Task 3:**
    - "The budget assumes the worst case" was wrong and is replaced: the moment a Page is cut into slices is not counted.
    - Apple's `CGContext.makeImage()` text, which the slices rely on, is quoted.
    - The glossary's words to avoid for a Cover and for a Source no longer appear outside Apple's quotes.
    - The cache and `footprint` are defined.
    - A Page coming back on screen shows a blank space while it is decoded again, not the placeholder.
  - **Task 4:**
    - The lazy stack's definition no longer says it "guesses", which was not Apple's word.
    - The zoom bullet says how zoom differs from a single Page.
    - The double-tap cause separates what is known, inferred and documented.
    - The end-of-strip consequence of counting only the reader's scrolling is added.
    - The slices row of the measurements table is in bytes.
    - "3 rows" at the 24-Page open is now "3 of the 7".
  - **Throughout:** outside Apple's quotes and code names, a Page is no longer called by the glossary's words to avoid for it.

### Gate

- `./scripts/format.sh --check`: clean.
- `SIMULATOR=F9304E8C-40F4-4962-A836-C10615C7DC16 SKIP_LAUNCH=1 ./scripts/verify.sh`: exit 0. Format clean; iOS and macOS builds succeeded; FolioCore's 90 tests passed before each platform's app tests, which passed on iOS and macOS (118 on macOS); the launch step was skipped. This task changed no code, so the run only confirms the branch is still green.
- The glossary's words to avoid were searched for in the four changed documents. They appear only inside Apple's quotes and names (including "security-scoped bookmarks" in `CLAUDE.md`), in the design log's record of the term the owner rejected and its mention of ImageIO's call, and in the ledger's file name.

### Not checked

- No new measurement was made. The plan asked for a fresh measurement of an 800 x 12,000 sample Page dropped into a Book, and it was not repeated in Task 5. The memory table below uses Task 3's decoded sizes, measured on the Mac (including that 800 x 12,000 Page), and Task 4's on-screen figures, measured on the iPhone simulator for a 600 x 12,000 Page. A measurement on a device is on the check list (iPhone items 6 and 12).
- The app was not run for this task; it changes documents only.

## Memory for tall Pages

Measured in Tasks 3 and 4; nothing here was measured on a device. The plan's fresh measurement of an 800 x 12,000 sample Page in a Book was not repeated in Task 5: the 800 x 12,000 figures below are Task 3's decoded sizes on the Mac, the on-screen figures are Task 4's for a 600 x 12,000 Page on the iPhone simulator, and a measurement on a device is on the check list (iPhone items 6 and 12). *Slices held* is the cache's own count of the bytes of the bands it keeps (rows times bytes per row). *The app's memory* is what `footprint` reports. A MB here is 1,048,576 bytes, the unit the budgets are set in, so 96 MB is 100,663,296 bytes.

| What | Where | Result |
| --- | --- | --- |
| An 800 x 12,000 Page decoded for an iPhone (screen 1,179 pixels wide, per-Page budget 96 MB) | the Mac, Task 3 | kept at its own 800 pixels wide; 6 slices; 38,400,000 bytes (36.6 MB); 0.03 s |
| The same Page decoded for a Mac (screen 2,880 pixels wide, 256 MB) | the Mac, Task 3 | the same: 36.6 MB; 0.03 s |
| A 3,000 x 40,000 Page decoded for an iPhone | the Mac, Task 3 | at the screen's width, 1,179 x 15,720; 8 slices; 74,449,920 bytes (71.0 MB); 0.19 s |
| The same Page decoded for a Mac | the Mac, Task 3 | lowered to 2,243 x 29,907; 15 slices; 268,923,744 bytes (256.5 MB, 0.2% over the budget because of row padding); 0.43 s |
| The app's memory while cutting the 1,179 x 15,720 Page | the Mac, Task 3 | about 76 MB (the slices' 71 MB and 5 MB for the rest of the app); about 6 MB while the slices were held but not drawn; 77 MB once every slice was read |
| Slices held in the 24-Page Book with a 600 x 12,000 Page (Strip Mixed), plain stack, the version kept | iPhone simulator, Task 4 | at most 50,720,000 bytes (48.4 MB) of the 288 MB cache budget. The 600 x 12,000 Page alone, decoded at its own 600 pixels wide, added 28,800,000 bytes (27.5 MB) |
| Slices held in the same Book with the lazy stack, since replaced | iPhone simulator, Task 4, before the plain stack | at most 109,120,000 bytes (104.1 MB) of 288 MB, at the end of the strip; 45,440,000 bytes (43.3 MB) at Page 5. The app's memory at the same time: 43 MB |
| The app's memory in the 1,000-Page Book after a fast scroll from Page 1 to Page 428 | iPhone simulator, Task 4 | 67 MB |

What this means for a reader:

- On an iPhone, even the tallest Page measured stays inside its 96 MB share. The Pages held at once stayed far below the 288 MB cache budget.
- The app's memory is lower than the slices held. As observed on the Mac, slices that are held but not being drawn cost less than their byte count. The budgets count the full byte count, which is the safe side.
- Two things are not counted by the budgets:
  - while a Page is being cut into slices, its whole decoded picture and its slices can both be in memory, up to about twice that Page's share (on the Mac this was observed not to happen for one Page);
  - on the Mac, a very wide and tall Page can be 0.2% over its share.

## Rulings made on the owner's behalf

Every ruling the controller (the agent that coordinated the implementation tasks) made during this slice, taken from its running record, the ledger (`.superpowers/sdd/2026-11-09-reading-mode/progress.md`). Each is in plain words, with what you would see if it was wrong. The *brief* is the written instructions each task was given.

**Ruling 1: the closing lines of each commit message.** Every commit ends with the two lines the owner pasted, naming "Claude Fable 5.1" and this session, not the lines the tool suggests. If wrong: only those two lines of text in each commit are off (the agents that did the work ran on other models than the one named). Nothing in the app is affected.

**Ruling 2: one number in the test of the top-of-the-screen rule.** The test uses a strip of three Pages, 600, 400 and 200 points tall, on a 500-point screen. There a scroll of 999 points is tested as the last Page, not the second as the plan had it: that strip's end is at 700, and the design says the last Page is "on" at the very end. If wrong: one test number. The rule itself is the design's, so nothing a reader sees changes.

**Ruling 3: the memory limits in the cache tests.** They are worked out from the measured size of one tiny decoded test Page, so exactly two Pages fit and a third does not. The plan's fixed numbers were so large that the cache would never have let anything go, so the test could not check what it claims. If wrong: test numbers only.

**Ruling 4: one implementation log.** One log for the whole slice (this file), with a section per task, finished in Task 5, instead of a log for every commit. If wrong: only where the record lives; nothing in the app.

**Ruling 5: one word added early.** Task 1 added the new event's name to one existing list in the Library screen's model, so the app kept building after Task 1; the plan had it in Task 2. If wrong: nothing; the same one-word change landed one commit earlier.

**Ruling 6: what the strip's scroll report carries.** It carries both how far the strip is scrolled and how tall the visible area is, both taken from what Apple's scroll view reports about its own position and size. The top-of-the-screen rule needs both, and the plan's version gave only the first. If wrong: only how one part of the code names these two numbers; nothing a reader sees.

**Ruling 7, as first written: hand checks on the Mac.** Agents were to check the Mac app only as far as they could drive it, and report anything they could not see as not checked.

**Ruling 7, as amended after an incident: no input to the owner's Mac.** Agents send no input of any kind to the owner's Mac: no keystrokes, clicks or pointer moves, and no scripts or tools that make them. They drive only the iOS Simulator. Every Mac item is reported as not checked and is on the owner's list.

- The incident: under the first wording, a Task 4 agent sent ⌘I, ⌘⇧G, a typed folder path and Return to the Mac. They landed in another window, apparently a terminal and possibly a running agent session.
- An iTerm2 "Quit iTerm2?" dialog was showing afterwards; whether the keystrokes caused it is unknown.
- If wrong: nothing on the Mac has been checked by anyone but you, so every Mac item on the list is open.

**Ruling 8: the width test for a very large Page.** The plan's test expected a 3,000 x 40,000 pixel Page on an iPhone to need a narrower width than the screen's to fit the 96 MB budget. At the screen's 1,179 pixels it needs only 74,449,920 bytes (71.0 MB, counting a MB as 1,048,576 bytes as the budgets do), so it fits. The test became two: at 96 MB the width is the screen's; with a 32 MB budget it is lowered, and one pixel wider would not fit. If wrong: test numbers only; the rule is unchanged.

**Ruling 9: the memory budget is applied after every decode.** The cache gets back within its budget after every single Page it decodes, not once after decoding a group of up to four as the plan said. The design's "memory stays within a stated budget however tall they are" is binding. Before, a slider jump could briefly hold about seven Pages' worth: about 672 MB on an iPhone, against 288 MB. If wrong: the cache lets go more often. A Page just outside the two it always keeps may then be decoded again when the reader comes back to it, seen as a moment's blank space before it appears.

**Ruling 10: only the reader's scrolling moves the Page being read (amended by ruling 13).** The strip changes the counter and the Reading Position only while Apple's *scroll phase* says the reader is scrolling. The scroll phase is what the scroll view says it is doing: dragged, coasting, moved by the app, touched, or still. Opening, switching, the slider and the keys move the strip without counting as reading.

This replaced the plan's mechanism. The scroll view reports where it is once when the strip first appears, before it is moved to the Reading Position's Page. Apple does not document that report, and when it counted as reading it saved Page 1 every time a Book opened in Vertical.

If wrong:

- On the Mac, scrolling with the wheel, the trackpad or the keyboard might not move the counter, if the system does not report it as the reader scrolling. Not checked; Mac items 2 and 9.
- After a jump near the end, the counter keeps the Page asked for rather than the last Page (see "How the strip knows which Page you are on").
- If the strip's height changed while the reader rested, the counter would not follow until they next scrolled.

**Ruling 11: the strip appears only once every Page's size is known.** Every Page's pixel size is read before the strip is shown, from the start of its stored data and without decoding. The plan had squares first and real heights later, but heights arriving late would move Pages under the reader, which the design rules out. If wrong: a blank moment when a Vertical Book opens. On the simulator it was 0.01 to 0.02 s for 24 Pages and 0.06 to 0.22 s for 1,000; not measured on a device.

**Ruling 12: a plain stack, and a rule for which Pages are decoded.** Each Page in the strip has a *row*, the space kept for it on screen at that Page's height. The strip makes every row before showing anything (a plain stack), instead of the plan's lazy stack, which makes rows only as they near the screen. Apple says lazy stacks give up some accuracy in where rows sit, and on the simulator Pages were thousands of points from their known heights after a long jump. In a plain stack every row is made at once, so a row being made can no longer be the signal to decode its Page. Instead a small tested rule works out, from where the strip is scrolled, which Pages to decode: the Pages on screen plus one each side, more when they are short. The other way Apple offers, telling the app when a row becomes visible, needs an amount of the row that must be visible, and any amount chosen would have been a guess. If wrong: an empty row exists for every Page from the moment the Book opens, so a Book of thousands of Pages could open more slowly or scroll less smoothly on an older phone than a lazy stack would. Not measured on a device; iPhone item 12.

**Ruling 13: a finger that has not moved is not scrolling.** This amends ruling 10: only dragging and coasting count, not "tracking", which Apple describes as a finger down where "the user hasn't started a scroll". Before, a tap at the end of the strip could have saved the last Page while the counter showed the one before. If wrong: none seen; a drag reports dragging as soon as it moves. Tracking was never seen on the simulator, so this rests on Apple's text.

**Ruling 14: a change of size keeps the reader's place inside the Page.** The zoom or the width can change through a pinch, a double tap, turning the device or resizing a Mac window. The strip then keeps the same point of the Page at the top under the top of the screen, as a fraction of that Page's height, instead of jumping to the Page's top. It does this through Apple's documented way of scrolling to an exact position. If wrong: after a resize the reader can be a few points from where they were; the counter is not affected.

**Ruling 15: Page heights on the pixel grid.** The *pixel grid* is the screen's own dots; an iPhone has 3 per point. On the simulator the scroll view was seen to come to rest only on whole pixels; this is observed, and Apple does not document it. Each Page's height is rounded to whole screen pixels, so every Page's top is on that grid. The app asks the screen how many pixels it has per point, rather than assuming a number, so this holds on every screen.

The defect was reproduced first: a jump stopped a fraction of a point above a Page's top, and the strip took the Page before it to be at the top. A jump back to that earlier Page then did nothing, leaving the counter on the earlier Page with the later one on screen.

If wrong: each Page differs from its true proportions by under one pixel.

**Ruling 16: the double tap zoom is not animated.** The double tap changes the zoom at once, so the strip already has its new size when it is moved to keep the reader's place. Apple says the scroll view "will clamp" a requested position to "the size of its actual content". With the animation, a double tap deep in the strip landed on another Page or a blank screen. No timer, delay or second move was added. If wrong: the double tap snaps instead of easing. The design leaves animation to the builder and does not require it.

### Items left for later

The ledger also holds notes deferred to Task 5 or to a final round of code fixes. Each is listed here with where it stands and what a user would see if it were left.

Done in Task 5 (this log's wording; see "Task 5: What Changed"):

- Task 1: "token" and "test double" in the log. They had already been replaced ("one word added to a list", "stand-in storage"); checked.
- Task 2: SwiftData carrying the data across "by itself" is labelled observed; "the proof is the test" is now evidence; stage, stage list, probe and log-only are defined.
- Task 3:
  - "The budget assumes the worst case" is reworded.
  - Apple's `CGContext.makeImage()` text is quoted.
  - The glossary's words to avoid for a Cover and for a Source (outside Apple's quotes) and the undefined `footprint` are fixed.
- Task 4:
  - The end-of-strip case after a jump is stated.
  - "Guesses for the rest" and "Zoom works as it does on a single Page" are corrected.
  - The double-tap cause is labelled known, inferred and documented.
  - The pinch check at Page 20 rather than 21 was already stated.
  - The sideways reset on every zoom step was already stated in fix round 2, and "both keep the reader's place" was already corrected there; checked.

On the owner's check list:

- Mac: whether the up and down arrows and Page Up and Page Down scroll the strip, and whether the counter follows (Mac item 9).
- Mac: resizing a window in Vertical (Mac item 11). The cache is rebuilt at every pixel of width change, so decodes repeat while dragging, and an old decode can overlap a new one. If left: resizing may stutter or show blank Pages until you stop.
- A two-finger pinch on a real phone, moving while pinching, and zooming out past fit, which was not tried on the simulator (iPhone item 9). The ledger's "letting go below fit" cannot be seen: the code holds the zoom at fit during the pinch, so what can be checked is that zooming out stops at fit.

For the final round of code fixes (not done; this task changes documents only):

- **Reading a saved Book back.** The code that turns a Book's saved form back into a Book (`Book.init(from:)`) is written out field by field and needs a comment to keep it in step with the Book's fields. If left: a setting added to a Book later could silently come back as its default after a relaunch.
- **The comment on `LibraryStorage.makeContainer(at:)`.** It says the upgrade stage makes an old store open, which the test could not show. If left: nothing a user sees; a later change might rely on the stage more than the evidence allows.
- **The test `v1StoreOpensAsPageByPage`.** It should say it also passes with no stages. Nothing a user sees.
- **The budget comment in `SlicedPage.swift`.** It overstates how exact the per-Page budget is; fix the comment, or count rows without their padding. If left: a very wide and tall Page on the Mac can take up to 0.2% more than 256 MB.
- **A failure that leaves no log line.** When drawing a slice fails, `slices(of:)` gives nothing without writing a log line, while the other failures log. If left: the reader sees the placeholder for that Page, as for any Page that cannot be shown, but the system log does not say why.
- **The shared test-Page writer.** It lives in one test file and repeats drawing code from another, and one check should stop the test outright when writing the test Page fails. Nothing a user sees.
- **Missing tests.**
  - The width rule exactly at the budget. Nothing a user sees.
  - The order in which the strip's cache decodes during a prefetch has no test of its own, and one test's bound is loose. If left: nothing a reader sees today, because nothing in the app calls that prefetch (`SlicedPageCache.prefetch(around:)`); only the tests do. The strip asks the cache for each Page on screen itself.
  - The rule that only the reader's scrolling counts, and the check that skips a jump to the Page already at the top, live inside the screen's code with no test of their own; moving them into a small piece of code of their own, outside the screen, would let tests check them. If left: a later change could bring back a swallowed jump without any test failing.
- **Two small differences from the brief.** The strip's geometry, once worked out, cannot be changed afterwards, where the brief described it as changeable; and the cache's prefetch makes whatever calls it wait until it finishes, where it could have been written not to. Recorded, no change planned; nothing a user sees (and nothing in the app calls that prefetch).
- **Two code comments.** One gives the wrong reason (`turn(by:)` in `ReadingView`). One says too much: in `VerticalStripView`, a jump made while the strip coasts is recorded when the coasting ends. Nothing a user sees.
- **The list of Page locations.** `ReadingView` rebuilds it (1,000 entries for a 1,000-Page Book) each time SwiftUI re-creates the screen; it should be made once. If left: a little extra work on each redraw in very long Books; not measured.
- **Which Pages are decoded after a zoom.** This is worked out only when the scroll view reports a move. A width or zoom change that leaves the scroll position where it was keeps the Pages chosen for the old size; the final reviewer is to check whether this still matters after ruling 16. If left: after zooming out where the position does not change (at the very top of the strip), a Page that came on screen might stay blank until the next scroll.

Noted by the implementers, with no ruling yet:

- The Human Interface Guidelines say every Mac toolbar item should also be a menu bar command; there is no Reading Mode menu command. If left: on the Mac the Reading Mode can be chosen only from the toolbar.
- A warning in `ReadingView.swift`, there before this slice, does not fail the build although the settings say warnings are errors. If left: nothing a user sees, but the warnings-as-errors rule is not enforced for that kind of warning.
- One Page is decoded for nothing when a Vertical Book opens (about 2.9 million bytes in the case measured). It is the Page at the top of the strip, before the jump to the Reading Position's Page.
- A strip shorter than the screen, such as a one-Page Book, sits in the middle of the screen, not at its top.

## Commits

| Commit | Subject |
| --- | --- |
| a1e290d | feat(library): Books remember a Reading Mode; chooseReadingMode announces ReadingModeChanged |
| ddf450e | feat(persistence): schema V2 stores a Book's Reading Mode; the model chooses it log-only |
| 0bc1bae | feat(reading): strip geometry rule, pixel sizes, width rule, slices and a budgeted cache for Vertical |
| 4d69086 | fix(reading): the cache applies its budget after every decode, not once after a prefetch |
| 1012734 | feat(reading): Vertical Reading Mode as one strip of touching Pages, chosen from the chrome |
| 43f8746 | fix(reading): the strip counts only the reader's scrolling, keeps their place inside a Page when zoomed, and snaps Page heights to the pixel grid |
| 466ac34 | fix(reading): double tap zoom keeps the reader's place by not animating the size change |
| 4d01b80 | docs(reading): record the Reading Mode rulings and the owner's check list |
| (this) | docs(reading): correct the owner's check list and label observed behaviour as observed |
