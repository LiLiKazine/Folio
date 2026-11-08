# Folio: Local-First Comic Reader — Design

Date: 2026-11-08
Status: ready for approval

## Intent

Folio is a comic reader for Apple devices that works entirely offline. The
owner already has comics downloaded onto their phone as folders of page
images (or zips of such folders). Today there is no good way to read them.
Folio lets them import those files, keeps a library on the device, and
reads them page by page.

"Local-first" here means: the app never requires a network connection, has
no account, no server, and no telemetry. Everything the user imports lives
on the device.

## Goals

- Import a folder of loose page images, or a zip containing such a folder,
  from the Files app (iOS/iPadOS) or Finder (macOS). One item per import;
  a folder with subfolders is one comic with its pages flattened.
- Show imported comics in a library with cover thumbnails.
- Read a comic by swiping page by page, left to right.
- Remember the last-read page per comic across launches.
- Run natively on iPhone, iPad, and Apple-silicon Mac, adapting layout per
  Apple's Human Interface Guidelines
  (https://developer.apple.com/design/human-interface-guidelines).
- Any device orientation is allowed.

## Non-goals (first version)

- CBZ, CBR, PDF, EPUB, or any format other than image folders and zips of
  image folders. The import pipeline should make these easy to add later.
- Right-to-left (manga) reading direction.
- Vertical/webtoon scrolling.
- Sync between devices, iCloud, or any cloud storage.
- Batch import (several folders or zips in one go).
- Device backup of imported comics: the comics directory is excluded from
  iCloud and Finder backups for now. Library metadata may be backed up.
- Series grouping, metadata lookup, tags, or search.
- Editing, annotating, or exporting pages.

## Anti-goals

- Any network dependency at runtime. The app must behave identically in
  airplane mode.
- Reading from the original file location. Once imported, the comic must
  keep working if the user deletes or moves the source in Files.
- A phone layout stretched onto iPad or Mac. Each platform should feel
  native per HIG.
- Third-party dependencies in the first version.

## Constraints

- Platforms: iOS 26, iPadOS 26, macOS 26 (Tahoe), Apple silicon only on Mac.
  (Builder's call: current OS releases only; raise if a lower deployment
  target is wanted.)
- Language and UI: Swift 6 with strict concurrency, SwiftUI, one
  multiplatform app target.
- Storage: comics are copied into the app's Application Support directory
  on import, with the comics directory marked excluded from backup. Library metadata (title, page list, cover, last-read page,
  import date) is persisted with SwiftData.
- Zip extraction uses Apple frameworks only. (Builder's call on mechanism;
  Foundation has no public zip API, so this likely means a small
  deflate-based reader built on Compression framework, or Archive
  framework where available. If that proves unworkable without a third
  party library, stop and raise it rather than adding a dependency.)
  Builder's call on scope: support stored and deflate entries, data
  descriptors, and UTF-8 filenames. Zip64 archives (over 4 GB or 65k
  entries) and encrypted zips are out of scope and must fail with a clear
  "unsupported zip" message rather than a generic error.
- Testing: Swift Testing for unit tests. Import parsing (file ordering,
  zip handling, image detection) must be covered by tests.
- Logging: OSLog.

## What the user decided

- Platforms: iPhone, iPad, M1-class Mac.
- Sources: folders of loose images; zips of such folders.
- Reader: swipe page by page; left to right only.
- No orientation lock.
- Single-item import; subfolders flattened into one comic.
- Imported comics excluded from device backup for now.
- Follow Apple HIG for per-device adaptation.

## Behaviour

### Import

1. User taps Import (toolbar on iOS/iPadOS; toolbar and File menu on Mac)
   and picks a folder or a .zip in the system file picker.
2. Folder: recursively collect image files (jpg, jpeg, png, heic, webp,
   gif). Zip: extract to a temporary directory, then treat as a folder.
   Ignore hidden files, `__MACOSX`, and non-image files.
3. Order pages by natural sort of their relative path (so `page2` comes
   before `page10`). Builder's call: nested subfolders are flattened in
   path order.
4. Copy pages into `Application Support/Comics/<uuid>/` and create a
   library record. Title defaults to the folder or zip name without
   extension. Cover is the first page.
5. Import runs off the main actor with a progress indicator; the library
   remains usable while importing. A failed import (no images found,
   unreadable zip) shows an alert and leaves no partial record.
6. Builder's call: if the picked item is an iCloud Drive placeholder that
   is not yet downloaded, import requests the download through file
   coordination and shows progress; if that fails (offline), the alert
   says the file has not been downloaded to this device yet.

### Library

- Grid of cover thumbnails with title and a subtle reading-progress
  indicator (e.g. "12 / 180" or a thin bar).
- Adaptive grid: more columns on iPad and Mac, per HIG sizing.
- Sorted by most recently read, then import date. Builder's call.
- Context menu / swipe: Delete (removes the copied files and record, with
  confirmation). Rename is a nice-to-have, not required.
- Empty state explains how to import.

### Reader

- Full-screen paged view, one page per screen, horizontal swipe, left to
  right. On Mac, left/right arrow keys and trackpad swipe also turn pages.
- Page fits the screen preserving aspect ratio; pinch to zoom, double-tap
  to toggle zoom; a zoomed page pans instead of turning until the edge is
  reached.
- Tap toggles chrome: title, page counter, a scrubber slider to jump pages,
  and a close button. Chrome hidden by default.
- Last-read page is saved whenever the current page changes.
- Pages are decoded lazily and downsampled to screen size to keep memory
  bounded on large comics. Pre-decode one page ahead and behind.

### Platform adaptation

- iPhone: single column navigation stack, library → reader push or
  full-screen cover.
- iPad: wider grid; reader is full screen; supports Split View and Slide
  Over sizes.
- Mac: standard window with toolbar; reader opens in the same window;
  keyboard navigation; File → Import menu item; supports drag-and-drop of
  a folder or zip onto the library window (nice-to-have).
- Dark mode, Dynamic Type for text, and the system accent colour are
  respected everywhere.

## Left to the builder

- Project layout, module boundaries, and the agent harness (scripts,
  CLAUDE.md, xcconfig).
- SwiftData schema details and migration strategy.
- Exact zip reading mechanism within the no-third-party constraint.
- Thumbnail generation and caching strategy.
- Exact grid sizes, spacing, and animation details, within HIG.
- Whether the reader on iPhone is a push or a full-screen cover.

## Future directions (not in scope, but don't block them)

- CBZ (trivially a zip), CBR, PDF.
- Right-to-left and vertical reading modes.
- Two-page spreads in landscape on iPad/Mac.
- iCloud sync of library and progress.
