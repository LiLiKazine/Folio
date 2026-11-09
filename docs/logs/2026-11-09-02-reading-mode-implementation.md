# 2026-11-09-02: Reading Mode — implementation

**Status:** In progress (Task 3 of 5 done)

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
schema when it first opens it.

## Task 1: Reading Mode in FolioCore

### What Changed

- `Domain/ReadingMode.swift` (new): `ReadingMode`, either `pageByPage` or
  `vertical`.
- `Domain/Book.swift`: a Book has a `readingMode`, defaulting to
  `pageByPage`. `Book`'s decoding was written out by hand so a Book saved
  without a Reading Mode (every stored Book) decodes as Page by Page; its
  encoding is still the synthesized one, unchanged apart from the new field.
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
  encoded without `readingMode` decodes as Page by Page and equals the
  original; a Vertical Book survives encode and decode.
- `LibraryErrorTests`: `chooseReadingMode` joins the operation switch and the
  forced-storage-failure cases (`books`, `update`), so a failing save is
  proven to throw `storage(.chooseReadingMode)`.

### What Was Discovered

- Neither stand-in storage keeps a list of the calls made to it. "Does not
  save" is therefore proven by making every Book `update` throw and showing that
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
- `Persistence/FolioSchema.swift`: `FolioSchemaV1` is now frozen, with its own
  copies of the two stored shapes (`FolioSchemaV1.BookModel` and
  `FolioSchemaV1.ImportModel`) inside it. `FolioSchemaV2` is the current
  schema: the same two shapes with the new field on the Book.
  `FolioMigrationPlan` lists both schemas and one stage, a *lightweight*
  migration (SwiftData carries the data across by itself because the only
  change is one added optional field; no code of ours runs) from V1 to V2.
- `Persistence/LibraryStorage.swift`: the real container is built from
  `FolioSchemaV2`. The on-disk path is now `makeContainer(at:)`, so a test can
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
Both are therefore marked as observed, and the proof is the test
`v1StoreOpensAsPageByPage`: it writes a store file on disk with the frozen V1
schema (a Book with Pages and a Reading Position, saved with the V1 copy of
the Book shape), closes it, opens the same file through the real
`makeContainer(at:)`, and checks the Book is there, unchanged, and reads as
Page by Page. It passes on macOS and on the iOS simulator.

Also observed: with the migration plan's stage list temporarily emptied, the
same test still passed, so SwiftData opened the V1 file in the V2 schema
without the stage. The stage stays, because the design and brief name it and
it states the intent; but this test proves "an old store opens", not "the
stage is what makes it open". I did not keep that probe in the code.

### Tests

- `SwiftDataRepositoriesTests`: a Book's Reading Mode roundtrips through
  storage (Vertical, then back to Page by Page); a stored Reading Mode that
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
pixels. None of this is on screen yet: Task 4 builds the Vertical strip on top
of these pieces.

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
  without decoding the image, and swaps them for a Page stored on its side.
  It gives nothing for a file that is not an image.
- `Reading/SlicedPage.swift` (new): the width rule (the smaller of the Page's
  own width and the screen's, lowered until width x height x 4 bytes fits the
  per-Page budget, never below 1), the decode, and the byte count of a set of
  slices.
- `Reading/SlicedPageCache.swift` (new): keeps the slices of the Pages read so
  far, decodes one at a time, and releases the least recently used Pages once
  the total is over the cache budget, never the Page at the top of the screen or
  the one after it.
- Tests: `StripGeometryTests`, `SlicedPageTests`, `SlicedPageCacheTests`, and
  two new tests in `PageImageTests`. `PNGFixture` (in `SlicedPageTests.swift`)
  writes the small test Pages.

### How a Page is decoded, and why slices are redrawn

`SlicedPage.decode` asks the system's image reader (ImageIO) for the Page at
the chosen width, then copies each band of rows into a new, independent picture
of its own. The whole decoded Page is a local value, so it is let go as soon as
`decode` returns and only the slices survive. Copying is deliberate: the cheaper
way, cropping, hands back a picture that Apple documents as keeping the
original alive (quoted below), which would have kept every Page's whole decoded
image in memory behind its slices and made the byte count wrong.
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
- Whether the thumbnail's width comes out exactly as asked when only the longer
  side is limited. Observed in every case measured below: the decoded width
  equals the requested width, and the height equals the requested longer side
  (the Page's height at that width, rounded up).
- Whether ImageIO decodes the whole Page at once. Observed (macOS, a
  1,179 x 15,720 Page, through `footprint`): the decoded image was not resident
  in full beside the slices; memory while slicing was about the slices' own
  71 MB plus the app's 5 MB, not double. Not documented, so this is not relied on
  for correctness; the budget assumes the worst case.
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
  on a 1,179-wide screen with the 96 MB budget, 1,179 pixels wide takes about
  74 MB, which fits, so "one pixel wider would not fit" is false there. The
  test was split in two: at 96 MB the width is the screen's 1,179; with a 32 MB
  budget it is lowered, and one pixel wider no longer fits.
- A test I first wrote to show that slices own their pixels (the length of each
  slice's data equals its rows times bytes per row) passed for cropped slices
  as well, so it proved nothing and was removed.
- A freshly decoded Page is read lazily and slices may cost little while
  untouched (see "observed" above); the budgets and the byte count deliberately
  ignore that.

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
