# Decisions

Why this project is set up the way it is. Append as decisions are made;
`structured-commit` writes longer entries to `docs/logs/`.

## 2026-11-08: Project bootstrap

**Platforms:** iOS and macOS

**Language:** Swift 6 with `SWIFT_STRICT_CONCURRENCY = complete` and
warnings-as-errors. These live in `app/Config/Shared.xcconfig` rather than in
documentation, so a green build is what proves they are in effect.

**Build settings in xcconfig, project committed.** The `.xcodeproj` uses
synchronized folder groups, so adding a source file never edits the pbxproj, and
every setting worth reading is text in `app/Config/`. No XcodeGen or Tuist
dependency.

**Observability is Apple-native.** OSLog now; MetricKit and App Store Connect
analytics when needed. No third-party SDK was added — that decision was left
open rather than made by default.

**An SPM core package was created** (`app/FolioCore/`).
Domain logic lives there so it can be tested headlessly in seconds rather than
through a simulator, which keeps the fast feedback loop fast. It is linked into the
app target at bootstrap, and the app's entry point imports it, so the compiler
enforces the link.

**Warnings-as-errors reaches the package through `scripts/test.sh`, not through
`Package.swift`.** Xcode compiles package dependencies with `-suppress-warnings`,
which conflicts fatally with a `.treatAllWarnings(as: .error)` in the manifest once
the package is linked into a target — it fails every configuration, including an
archive. Project-level `SWIFT_SUPPRESS_WARNINGS = NO` does not reach package
targets. The trade-off, worth stating plainly: a warning in the package fails
`./scripts/test.sh` and CI, but is suppressed when Xcode builds the app.

**App Sandbox is on**, with `files.user-selected.read-only` and
`files.bookmarks.app-scope` and no network entitlement.
Retrofitting the sandbox is architectural — a path `String` stops being a valid
handle and persistence must move to security-scoped bookmarks — so it is cheaper
to start inside the container and add entitlements as needed. The bootstrap
shipped `network.client`; it was removed in the Library and Import slice because
Folio works without any network. If one is ever needed, note that sandbox network
denial presents as a generic connection failure rather than a permissions error.

**Signing.** macOS is signed ad-hoc (`CODE_SIGN_IDENTITY = -`) with no
development team, so the project builds and runs with no Apple Developer account
configured. Developer ID, notarization, and provisioning are handled later by
the `asc-signing-setup` and `asc-notarization` skills. Hardened runtime is off;
it is a notarization prerequisite, not a local-run one.

**Distribution target is the App Store**, on iPhone, iPad, and Apple-silicon
Mac. This is why the sandbox stays on and why the Mac build is expected to pass
App Store prerequisites rather than ship as a notarized download.

**Deployment targets are iOS 26 and macOS 26.** Xcode 27.1 is installed, so
these are the previous major releases per the "latest minus one" rule. The design
document for the first feature assumes current-generation SwiftUI and SwiftData.

**Persistence is SwiftData** for the library index (comic records, page lists,
last-read position). Comic page images are copied into Application Support on
import and excluded from device backup. Decided during the first-feature
brainstorm so the import work does not re-litigate it; see
`docs/superpowers/specs/2026-11-08-folio-comic-reader-design.md`.

**No third-party dependencies**, including for zip reading. The first version
reads stored and deflate zip entries on Apple's Compression framework. If that
proves unworkable, the rule is to stop and raise it rather than add a package.

**Simulator resolution is by UDID, not name.** `scripts/_common.sh` picks the
newest available iPhone simulator by device identifier. On this machine two
simulators share the name "iPhone Duo", and `xcodebuild` refuses an ambiguous
name; a UDID is unique by construction and every `simctl` subcommand accepts it.
`SIMULATOR=` still overrides with either a UDID or a unique name.

**Launch screenshots handle multi-display simulators.** "iPhone Duo" exposes
two displays and `simctl io screenshot` fails with EINVAL until one is named.
`scripts/run.sh` retries on the primary display when that error appears, so the
gate passes on foldable simulators without a manual flag.

## 2026-11-08: Library and Import slice

**Import is persisted at creation and run serially.** An Import is written to
the store the moment the user picks a Source, with a status (Queued, In
Progress, Failed, Completed), and the Library promotes the oldest Queued Import
only when none is In Progress. A killed run therefore resumes at next launch,
Retry has a record to act on, and memory and disk churn stay bounded on large
zips. The Book record is written last, so there is never a half Book.

**The Import gets its Book id before the pipeline runs.** The plan wrote the
Book and then marked the Import Completed, which could leave a duplicate Book if
the process died between the two writes. The Import now receives its Book id
when it goes In Progress; launch recovery and Retry first look for a Book with
that id and, if one exists, mark the Import Completed instead of re-running it.
The cost is that In Progress and Failed Imports carry a Book id that points at
no Book, so code must never read a non-nil id as "has a Book".

**The SwiftData store lives inside the Books directory.** The Library store
sits beside the Book folders in the backup-excluded directory under Application
Support, so a restored device cannot have records without Pages or Pages
without records. Launch reconciliation only considers folders whose name parses
as a UUID, which leaves the store files alone.

**Import staging lives in the system temporary directory.** Each Import stages
its Pages in a fresh item-replacement directory that the system supplies for
the Books directory's volume (`FileManager.url(for: .itemReplacementDirectory,
appropriateFor:)`), so the system purges whatever a killed Import leaves and
the final move into the Books directory stays a single atomic rename. If the
system cannot supply one, staging falls back to a `FolioImport` folder in the
temporary directory, which launch cleanup deletes; the final move uses
`rename(2)` rather than `FileManager.moveItem`, so a cross-volume staging folder
fails the Import with a storage failure instead of being copied. Books stay in
Application Support because Documents is for files the user manages and is
backed up by default.

**Zip reader scope.** The reader handles stored and deflate entries, data
descriptors, and UTF-8 names (with a CP437 fallback when the UTF-8 flag is
absent), on Apple's Compression framework and with no dependency. It rejects
zip64 and encrypted archives as unsupported, skips directory entries and
`__MACOSX`, and refuses entries that would escape the destination. Each entry
is decoded in memory, so a declared size over 256 MiB is rejected as
unsupported before anything is allocated; this keeps the simple `Data` in,
`Data` out interface while closing the zip-bomb hole, at the price of refusing
a single Page larger than that. CRC-32 is not verified because Compression has
no CRC function.

**Stale bookmarks are accepted.** When a stored security-scoped bookmark
resolves as stale, `FileSourceAccess` logs it and uses the resolved URL rather
than failing. Failing a Retry because a folder moved once would punish the user
for nothing. Refreshing and persisting a new bookmark needs an interface change
and is a follow-up; until then a Retry can still fail later if the Source moves
again.

**Two more failure reasons.** The glossary's reasons did not cover everything
the pipeline can hit, and mapping to an unrelated reason would mislead the
user. `storageFailure` ("Couldn't write to Folio's storage") covers file-system
errors during copy or move other than running out of space, which still reports
`notEnoughStorage`. `undecodablePage` covers a first Page that ImageIO cannot
decode, so no Cover can be made. If the storage capacity check itself throws,
the preflight is skipped and the Import proceeds.

**Reading Position is a 0-based index into the Book's Pages.** It matches the
domain value (an index into the ordered Pages); the UI shows "Page n+1 of N".
The reader slice must store it the same way.

**The app owns the Library event loop.** `LibraryModel.start()` first ran from
a window's `.task`, so closing a Mac window cancelled event handling for the
rest of the process. `FolioApp` now starts it once, in an unstructured Task kept
in `@State` beside the model and created the first time any scene body runs,
independent of window lifetime. The Task lives for the process, which is
acceptable for a single-model app. `LibraryModel` also takes the Books directory
explicitly, because the pipeline's directory is internal to `FolioCore` and
Cover lookup needs it.

**The Mac sandbox gains bookmark entitlements.** Creating a security-scoped
bookmark failed on macOS ("ScopedBookmarksAgent did not return error domain")
because the sandbox lacked them. `app/Config/macOS.entitlements` now includes
`com.apple.security.files.bookmarks.app-scope` and
`com.apple.security.files.user-selected.read-only`; Folio only reads a Source
and never writes back to it.

**Smaller rulings.** A Title is the Source's own name with only a `.zip`
extension stripped, so a folder called "Vol.3" keeps its dot. `FolioCore` logs
repository failures through its own OSLog logger (category "library") rather
than swallowing them: the failure path retries its Import update once and
always clears the in-memory running state. The slice was built on a feature
branch in place rather than a worktree, since nothing else was in flight.

## 2026-11-08: Visible Failures

Terms used below that are not in the glossary: *logging* is writing a line to
the system's diagnostic log, which the user never sees; a *typed throw* is a
Swift function that declares exactly which error type it can throw, so the
compiler rejects any other error escaping it; a *catch* is the code that
handles a failed step; the *store* is the database file where Books and Imports
are saved; a *record* is one saved row in the store (one Book or one Import);
the *Import scheduler* is the part of the Library that runs Queued Imports one
after another; *launch recovery* is the step at launch that puts interrupted
Imports back in the queue and tidies records; *SwiftUI* is Apple's
screen-building framework; "in memory" means held only while the app runs,
not saved.

**Every failure is presented, because logging is diagnostics, not an outcome.**
Before this slice, many failures (a rename that could not be saved, a Book
that could not be deleted) only wrote a log line, so the user saw the action
seem to work or silently do nothing. Now an action either visibly succeeds or
shows a Notice. The codebase rule in `CLAUDE.md` says a catch that only logs is
a defect unless a comment starting `// Log-only:` at that spot says why
nothing the user sees depends on it, and each operation has a test that forces
its failure and checks the Notice.

**The Library's failures are one typed `LibraryError`, enforced by the
compiler.** Every public Library operation now declares that it throws only
`LibraryError`, so a new failure path cannot reach the app as an unexplained
error: the code will not compile until it is mapped to a case that carries the
operation (such as "Rename" or "Delete Book") and so produces a Notice with
the right title. Anything unexpected inside an operation is logged and
reported as a storage failure for that operation.

**Failures with no caller become `LibraryStorageFailed` events.** Some work
happens in the background with nobody waiting for an answer: the Import
scheduler, launch recovery, tidying Book folders, deleting a Book's folder
after its record is gone. These announce `LibraryStorageFailed` with the
operation, and the app turns it into a Notice, so the user still hears that
what they see may be out of date.

**Notices queue, and only an exact repeat of the last one collapses.** If
several things fail, the user sees each Notice in turn, one at a time. A Notice
with the same title and message as the one queued just before it is dropped, so
one broken disk does not show the same Notice ten times. Different Notices
are never merged. In the worst case a fully broken store at launch shows
"Couldn't Open the Library" and then one "Couldn't Update the Library".

**One failure at launch gives one Notice.** When the Library's launch step
(`start()`) cannot read the in-progress Imports, the app also tries to reload
the Library and that reload fails for the same reason. The reload's failure is
only logged, because the "Couldn't Open the Library" Notice already says it.
The price is that a separate read failure in the same instant is hidden; we
accepted that. The same rule applies to the reload that follows a
`LibraryStorageFailed` event.

**An Import whose status cannot be saved is skipped until relaunch.** If a
Queued Import cannot be marked In Progress, and then cannot be marked Failed
either (a full disk, for example), the Import scheduler would pick it again
immediately and flood the user with Notices. It is now left alone for the rest
of the session, matching the Notice's "relaunch Folio" wording. The cost is one
relaunch for the user; the Import runs again after it.

**A file-picker failure is a Notice too.** If the system file picker itself
reports an error there is no Source name to show, but the principle admits no
exception: the Notice is titled "Couldn't Import" and says "Folio couldn't open
the file picker. Try again."

**How Notices are handed over on screen: only OK removes a Notice.** The
Library shows one Notice at a time in a system dialog (SwiftUI's `.alert`).
Pressing OK (or Escape) is the only thing that removes the Notice from the
queue. If the system closes the dialog any other way, the Notice stays first
in the queue and the screen shows it again. The next queued Notice appears only
after the previous dialog has fully closed, 150 ms later, because SwiftUI will
not reliably show a new dialog while the old one is still closing. The delay
was found by trying it, not from documentation, and nothing retries: if it
turns out too short on some device, the Notice would not appear and no later
Notice would either until Folio is relaunched. This was checked on the Mac and on a single-display iPhone
simulator.

**A Notice waits while another dialog on the Library screen is open.** The
Library screen can only show one dialog at a time: the file picker, the Rename
dialog, a delete confirmation, or a Notice. Before this fix, a Notice that
arrived while one of the others was open was silently refused by the system,
and the screen then believed a Notice was showing, so no Notice appeared again
for the rest of the session. Now the Notice waits in the queue and appears
150 ms after the other dialog closes. What the user sees: they finish or cancel
what they were doing, and the Notice follows. This was checked by hand with
the file picker on the Mac and on an iPhone simulator.

**The Library screen does not refresh itself until launch has finished.** The
screen asks for a fresh list of Books and Imports whenever it appears or the app
comes back to the front. At launch that request could arrive while the
Library was still tidying up, and with a broken store the user saw "Couldn't
Update the Library", then "Couldn't Open the Library", then the first again.
Now those requests do nothing until the Library has finished launching and
loaded the list once; launch itself reports any failure, once.

**The Library's launch step (`start()`) keeps its typed throw.** The plan said
it would stop throwing and announce an event instead. Task 1 had already made
it throw `.storage(.openLibrary)` when the in-progress Imports cannot be read,
and that stays: a caller is present, so the compiler makes sure the failure is
handled, and the app turns it into the "Couldn't Open the Library" Notice.
Failures for individual records inside the launch step have no caller and
become `LibraryStorageFailed(.openLibrary)` events. What the user sees: the
"Couldn't Open the Library" Notice once at launch, whichever way the failure
happened; never twice.

**Source not downloaded gets its own Notice copy.** The spec's copy table had
no row for a Source that is not downloaded to the device (for example in
iCloud). The Notice is titled "Couldn't Import “<Source>”" and reuses the
existing reason text "Not downloaded to this device", matching the Failed
card. Changing the wording later costs nothing.

**Process: a task could make the smallest edit in a later task's file.** The
plan's Task 3 removed the old failure message type that the Library screen
used, which would have left the app unable to compile until Task 4. Task 3 was
therefore allowed the minimal edit to the Library screen to keep the app
building, and Task 4 finished the presentation.

**An Import asked for while a Notice is showing opens the file picker right
after the Notice closes.** The Library screen can show only one dialog at a
time. Before this fix, pressing ⌘I (or the Import button) while a Notice or a
Rename or Delete confirmation was on screen did nothing, and after that the
file picker never opened again and no later Notice appeared until Folio was
relaunched. Now the request waits: once the user closes the dialog, the
file picker opens 150 ms later, the same pause a waiting Notice gets. Asking
several times while waiting still opens it once. If another Notice is waiting
too, whichever appears first is followed by the other.
