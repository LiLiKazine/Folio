# Library and Import — Design

Date: 2026-11-08
Status: ready for approval
Glossary: `CONTEXT.md` is authoritative. Capitalised terms below are glossary
terms and are used with exactly those meanings.

## Intent

The first slice of Folio: a Library screen that shows Books, and Import that
turns a folder or zip of images into a Book. There is no reader yet; opening a
Book does nothing beyond recording that it was opened. This slice exists so the
app has real content, real storage, and a real screen before the reader is
built on top.

The overall product design is in
`2026-11-08-folio-comic-reader-design.md`; where the two disagree this
document wins for the Library and Import, and that document should be
updated to use glossary terms when the reader slice is designed.

## Goals

- Import folders of images, or zips containing one. Each picked Source
  becomes an Import; Imports run one at a time in creation order.
- Show Books in an adaptive grid with Cover, Title, and page count.
- Show Imports that are In Progress or Failed in place in the grid, read from
  the database like Books, with progress or a Retry action.
- Retry a Failed Import, including one interrupted by the app being killed.
- Rename and delete Books.
- Run on iPhone, iPad, and Mac, following Apple's Human Interface Guidelines
  for each, with the grid adapting to width rather than device.
- Work with no network at all.

## Non-goals

- The reader. Reading Position is stored but never changes in this slice.
- Multi-select in the file picker, duplicate detection, merging Books,
  series grouping, search. (Several Imports can be queued by picking one
  Source at a time.)
- Reordering or prioritising the Import queue.
- A Book referring to its Source. Only the Import record does.
- Background execution time for Imports. An Import the system kills returns
  to Queued at next launch and resumes then.
- Reordering Pages (a later edition, but see the Page order constraint).
- Device backup of Pages. The Books directory is excluded from backup.
- Third-party dependencies.

## Anti-goals

- Half Books: a Book visible in the Library whose Pages are not all present.
- Reading from the Source location after Import.
- A stretched phone layout on iPad or Mac.
- Any code path that needs a network.

## Domain model

### Building blocks

- **Book** is the aggregate root. Pages belong to a Book and never exist on
  their own. Operations that touch Pages go through the Book.
- **Page** is a value inside a Book: a position in reading order and an image
  file. It has no identity of its own.
- **Library** is the collection of Books: where Books are added, listed, and
  removed.
- **Source** is a value held by an Import: the picked folder or zip, kept as
  a security-scoped bookmark plus its display name.
- **Import** is a persisted entity with identity and a status: Queued,
  In Progress, Failed, or Completed. It holds its Source, the Title it will produce,
  progress (Pages done and total), a failure reason when Failed, and the id
  of the Book it produced when Completed. Import records are kept after they
  end. (Owner's decision.)

### Invariants

1. A Book has at least one Page.
2. Page order is set at Import and owned by the Book. It is stored
   explicitly, never derived by re-sorting filenames after Import, so a later
   edition can reorder it.
3. Title is never empty.
4. A Book is in the Library only when all its Pages are in Folio's storage.
   This must hold even if the app is killed mid-Import.
5. Reading Position, when present, refers to a Page that exists in the Book.
6. An Import is Completed only when its Book exists; a Completed Import
   always refers to a Book, and a Book is referred to by exactly one Import.
   A Completed Import keeps its Book id as history even if the Book is later
   removed.
7. At most one Import is In Progress at a time. Whenever none is, the oldest
   Queued Import is promoted. This is what makes Imports serial.

### Operations

On the Library:
- Create an Import from a Source. It starts Queued. The Import control is
  always enabled.
- List Books in Library order: one sort key, last-opened time if the Book
  has been opened, otherwise imported time, newest first. A just-imported
  Book therefore appears at the top. (Builder's call.)
- Remove a Book, deleting its Pages from storage in the same action.

On an Import:
- Report progress as Pages copied so far out of total.
- Complete, producing a Book and recording its id.
- Fail with one of: no images found, unreadable zip, unsupported zip (zip64 or
  encrypted), Source not downloaded to this device, not enough storage,
  Source no longer available, cancelled.
- Cancel a Queued or In Progress Import, which records it as Failed with
  reason cancelled and nothing in storage. Emits ImportFailed.
- Retry a Failed Import: set it back to Queued under the same Import id, so
  the card stays in place and it takes its turn. Emits ImportQueued.
- Remove a Failed Import, deleting its record. Emits ImportRemoved.

On a Book:
- Rename to a non-empty Title.
- Open, which records the time. (The reader will later also set Reading
  Position.)

#### Domain events

Facts the model announces after they have happened. Each is named in the past
tense, carries only glossary values, and is the only way anything outside the
Library learns of a change.

- **ImportQueued** (Import id, Title it will get); also emitted on Retry
- **ImportStarted** (Import id, total Pages)
- **ImportProgressed** (Import id, Pages copied, total)
- **ImportCompleted** (Import id, the new Book)
- **ImportFailed** (Import id, Source name, failure reason)
- **ImportRemoved** (Import id)
- **BookRenamed** (Book id, new Title)
- **BookOpened** (Book id, time)
- **BookRemoved** (Book id)

In this slice the only subscriber is the Library screen. The grid itself is
derived from the database (Books plus Imports that are not Completed); the
events tell the screen when to refresh and drive the progress counter and
the one-time failure alert. The reader slice will subscribe to
BookOpened to set Reading Position. Events are in-process and not persisted.

### Repositories

The **BookRepository** and **ImportRepository** are the model's only doors to
persistence. Their interfaces are expressed in glossary terms and values:

BookRepository:
- fetch all Books in Library order
- fetch one Book by id
- add a Book
- update a Book (Title, Reading Position, last-opened time)
- remove a Book by id

ImportRepository:
- fetch Imports by status
- add an Import (status In Progress)
- update an Import (progress, status, failure reason, produced Book id)
- remove an Import by id

The SwiftData implementation lives in the app. Tests in FolioCore use an
in-memory implementation. Nothing in the domain or the views knows which
one is in use.

## Import rules

- A Source is a folder or a `.zip`. A zip is expanded to a temporary folder and
  then treated as a folder Source.
- Pages are the files with extensions jpg, jpeg, png, heic, webp, gif, found
  recursively. Hidden files, `__MACOSX`, and non-image files are ignored.
  Subfolders are flattened.
- Order is the natural sort of each file's relative path within the Source
  (`page2` before `page10`).
- Title defaults to the Source's own name without extension: the picked
  folder's name or the zip's filename, never a parent folder and never a
  folder inside the zip.
- Cover is the first Page in order. A file named "cover" gets no special
  treatment.
- Importing the same Source twice makes two Imports and two Books.
- Zip support covers stored and deflate entries, data descriptors, and UTF-8
  names. Zip64 and encrypted archives fail as "unsupported zip".
- An iCloud Drive placeholder that is not downloaded is downloaded first when
  possible; otherwise the Import fails as "not downloaded".
- Folder Sources in iCloud Drive: every file inside is downloaded first when
  possible; otherwise the Import fails as "not downloaded".

## Behaviour

Mockups: https://claude.ai/artifact/UfuRMEqUSKo3HM7iJndNhz

### Library screen

- Adaptive grid driven by available width: two columns at phone width, more
  as width grows. iPad Split View therefore gets the phone layout.
- Each Book card: Cover (2:3, rounded, subtle shadow), Title on one line
  truncated, then a second line reading "N pages" if never opened or
  "Page P of N" once a Reading Position exists, with a thin progress bar
  beneath in the latter case. A finished Book shows a full bar; no checkmark.
- Sorted in Library order (see Operations). The grid does not re-sort live
  while on screen; the order refreshes the next time the Library screen
  appears, so opening a Book never shuffles the grid under the user's finger.
  (Builder's call.)
- Empty state: a placeholder glyph, "No Books yet", one sentence telling the
  user to import a folder of images or a zip of one, and an "Import a Book"
  button.
- Import button in the navigation bar (plus icon). Always enabled; each
  picked Source becomes a Queued Import. Opens the system file picker filtered to folders and zip files.
- Imports that are not Completed appear as cards ahead of the Books: the
  In Progress one first, then Queued ones in creation order, then Failed
  ones. Each has a placeholder Cover and the Title it will get.
- In Progress: a spinner and "P of N" beneath. Action: Cancel.
- Queued: "Waiting" beneath. Action: Cancel.
- A Failed Import appears as a card in the same position with a placeholder
  Cover, a warning glyph, the Title it would get, and the failure reason on
  the second line. Its actions are Retry and Remove (context menu on all
  platforms, plus a Retry button on the card).
- Completed Imports are not shown; their Book is.
- Import failure: a one-time alert titled "Couldn't Import "<Source name>""
  with a reason the user can act on, shown at the moment of failure. The
  Failed card remains until retried or removed. The alert is not shown for a
  cancellation the user requested; the Failed card still remains.
- Book context menu (long-press on iPhone and iPad, right-click on Mac):
  Rename, Delete Book. Delete asks for confirmation.
- Opening a Book records it as opened and, in this slice, does nothing else
  visible. On iPhone and iPad a tap opens. On Mac a single click selects and
  a double click opens, per HIG; the selection model exists only in the Mac
  and iPad layers. (Builder's call.)

### Platform adaptation

- iPhone: navigation stack with large title "Library".
- iPad: same, more columns, plus a Select mode for multi-delete.
- Mac: standard window; File → Import… (⌘I); toolbar Import button; drag a
  folder or zip onto the window to Import; Delete key removes the selected
  Book after confirmation; right-click menu.
- Dark mode, Dynamic Type, and the system accent colour are respected.

## Architecture

### FolioCore (SPM package, no UI, no SwiftData)

Holds the domain and the Import pipeline, testable headlessly with fixture
folders and zips.

- `Book` value: id, Title, ordered Pages (filename list), Cover filename.
- Source scanning: folder URL in, ordered Page file URLs out, applying the
  Import rules above.
- Zip expansion on Apple's Compression framework, with typed failures for
  unreadable and unsupported archives.
- The Import operation: takes a Source URL and a destination directory,
  reports progress, copies Pages into a staging folder, generates the Cover
  thumbnail, and returns a `Book` value or a typed `ImportFailure`. Supports
  cancellation.
- `BookRepository` and `ImportRepository` protocols with in-memory
  implementations for tests.
- `Library` actor and the domain event stream (see Domain model).

All of this speaks in URLs and values. Nothing here imports SwiftUI or
SwiftData.

### App: storage (adapters)

- `SwiftDataBookRepository` and `SwiftDataImportRepository`: the app's
  implementations. One record per Book mirroring the `Book` value plus
  Reading Position, imported date, and last-opened date, with Page order as
  an explicit ordered list. One record per Import with status, Source
  bookmark data and display name, Title, progress, failure reason, produced
  Book id, and created and finished dates.
- A `Library` actor (in FolioCore, given a `BookRepository` and a Books
  directory URL) is the aggregate's home: it owns the Books directory under
  Application Support (excluded from backup), runs one Import at a time,
  emits the domain events above as an `AsyncStream`, and keeps records and
  files in step: Pages land in a
  staging folder and are moved into their final folder in one step on
  completion, then the Book record is inserted and the Import record is
  marked Completed with the Book id. The Import record is written when the
  Import starts, so an Import survives the app being killed as a record with
  status In Progress. Deleting a Book removes record
  and folder together.
- The SwiftData store file lives inside the Books directory, which is
  excluded from backup, so records and Page files are backed up (or not)
  together and a restore cannot yield records without files. On launch the
  Library deletes leftover staging folders, returns any In Progress Import
  to Queued so it resumes automatically (being killed is not a fault of the
  Source), removes any Book record whose folder is missing, and removes any
  folder with no record. (Builder's call.)
- The `Library` runs a scheduler: after launch recovery and after every
  Import ends, if no Import is In Progress it promotes the oldest Queued one
  and runs it. Imports therefore proceed serially from a persisted queue
  rather than as unmanaged concurrent tasks.

### App: views

- `LibraryView`, `BookCard`, `ImportingCard`, empty state, context menu,
  alerts. Views send operations to the `Library`, subscribe to its domain
  events, and never touch files or the repository directly.
- Platform-specific pieces (Mac menu commands, drag-and-drop, Delete key,
  iPad Select) are isolated so the shared views stay shared.

## Constraints

- Swift 6 strict concurrency, SwiftUI, SwiftData, Swift Testing, OSLog, as set
  up by the bootstrap. Warnings are errors.
- Deployment targets iOS 26 and macOS 26.
- No third-party dependencies. If zip reading on Compression framework proves
  unworkable, stop and raise it rather than adding one.
- Source access: the Import stores a security-scoped bookmark to its Source
  and resolves it on Retry, starting and stopping security-scoped access
  around the copy. A bookmark that no longer resolves fails the Import as
  "Source no longer available".
- Tests: Source scanning (ordering, filtering, flattening), zip expansion
  (stored, deflate, data descriptors, UTF-8 names, zip64 rejection, encrypted
  rejection), Title derivation, Cover selection, Import atomicity
  (cancellation and simulated failure leave no Pages behind and the Import
  record reads Failed), Retry under the same id, serial scheduling (two
  Queued Imports run one after the other, never together), and launch
  recovery (In Progress returns to Queued and resumes) must be covered in
  FolioCore.

## Left to the builder

- SwiftData schema details, how Page order is encoded, and how the Source
  bookmark is stored.
- Thumbnail size and format for the Cover.
- Exact grid sizing, spacing, and animations within HIG.
- How progress is bridged from the Import to the card.
- How the Mac and iPad-only pieces are isolated from shared views.
- Whether fixture zips for tests are checked in or generated in the test.
