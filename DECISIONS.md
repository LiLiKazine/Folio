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

_Superseded on 2026-11-08 by the Presentation Coordinator section._

**A Notice waits while another dialog on the Library screen is open.** The
Library screen can only show one dialog at a time: the file picker, the Rename
dialog, a delete confirmation, or a Notice. Before this fix, a Notice that
arrived while one of the others was open was silently refused by the system,
and the screen then believed a Notice was showing, so no Notice appeared again
for the rest of the session. Now the Notice waits in the queue and appears
150 ms after the other dialog closes. What the user sees: they finish or cancel
what they were doing, and the Notice follows. This was checked by hand with
the file picker on the Mac and on an iPhone simulator.

_Superseded on 2026-11-08 by the Presentation Coordinator section._

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

**An Import asked for while a Notice is showing opens the file picker
shortly after the Notice has closed.** The Library screen can show only one dialog at a
time. Before this fix, pressing ⌘I (or the Import button) while a Notice or a
Rename or Delete confirmation was on screen did nothing, and after that the
file picker never opened again and no later Notice appeared until Folio was
relaunched. Now the request waits: once the user closes the dialog, the
file picker opens 150 ms later, the same pause a waiting Notice gets. Asking
several times while waiting still opens it once. If another Notice is waiting
too, whichever appears first is followed by the other.

_Superseded on 2026-11-08 by the Presentation Coordinator section._

## 2026-11-08: Presentation Coordinator

A *dialog* here is anything the Library screen puts over the grid and waits
for the user to answer: a Notice about something the user just did, the file
picker, the Rename box, and the Delete confirmations. A *status line* is a
small message at the top of the Library, with a Close control, that does not
block anything.

**One source of truth for what is on screen.** The Library screen used to
keep a separate on/off flag for each dialog, plus a list of checks for "is
another dialog already up". SwiftUI (Apple's screen-building framework) shows
one dialog at a time and its documentation says nothing about what happens
when a second is requested while one is up. In practice the second was
refused without a word, and the user saw the file picker never open again
until relaunch. Now the screen holds one queue of requested dialogs; only the
first is shown, and the next appears when SwiftUI reports the first is closed.
What the user experiences: pressing ⌘I (or the plus button) while a Notice is
showing opens the picker as soon as the Notice is closed, and two Notices in
a row appear one after the other. The design rests on what Apple documents:
a presentation's condition is a binding (a value the screen reads and that
SwiftUI can also write back), so "SwiftUI can reset the underlying
value when the user dismisses the presentation"; for a dialog "the system
sets this value to false and dismisses" when an action is pressed; the file
picker sets its flag to false when finished or cancelled; and `sheet(item:)`
says "If item changes, the system dismisses the sheet and replaces it with a
new one". Closing is the only signal we use.

**No delays and no guessed signals.** The old code waited 150 ms after a
dialog closed before showing the next, a number found by trying. A delay can
be too short on a slower device, and then a dialog is lost with no sign. We
also do not poll (check again and again, on a timer, whether something has
happened), and we do not invent a "finished" signal that SwiftUI does
not give. The only move to the next dialog is SwiftUI's own report that the
current one closed.

**Background Notices are a status line, not a dialog.** Apple's Human
Interface Guidelines say "Avoid using an alert merely to provide information"
and "Avoid showing an alert when your app starts" ("alert" is their word for
a dialog). A Notice about something the user did stays a dialog, because it
answers their action. A Notice about a failure in the background (a
LibraryStorageFailed event, or the Library failing to open or refresh at
launch) now appears as a status line with the same text. What the user
experiences: a launch-time problem no longer greets them with a dialog, and
fewer dialogs queue behind one another. A dialog Notice and a status line
Notice with identical text never merge into one, so a dialog cannot vanish
into the status line.

**Asking for the same thing twice is one request.** If a request is already
showing or waiting, asking for it again is ignored. Pressing ⌘I twice while
the picker waits opens it once, and a Rename for the same Book is not queued
twice. This is a rule about identical requests, not a guess about what the
user meant.

**Each dialog is a fresh presentation.** Two dialogs of the same kind in a
row (two Notices) could leave SwiftUI's on/off value true all the way
through, so it might never show the second and the queue would wait forever.
Each dialog now hangs on an invisible helper view whose identity changes with
every dialog; SwiftUI documents that a changed identity makes a new view. The
grid itself is not given a new identity, so its scroll position is kept.
That a view which appears already asking to present will present its dialog
is observed behaviour, not documented behaviour; the owner's manual check on
Mac, iPhone, and iPad is the evidence (see the log's checklist).

**Repeats are collapsed per kind.** A Notice identical to the one just queued
is still not added again, but now only against Notices of the same kind
(dialog or status line). Costs nothing visible.

**What was removed, and why each was a workaround.** The per-dialog flags
existed only because there was no single source of truth. The import request
gate (a small object that held a picker request until other dialogs closed)
and its tests, and the "is another dialog up" checks, were guard lists for
the same gap. The 150 ms settle delay was a guessed timing. The debug hook
`FOLIO_DEBUG_NOTICES`, which made a DEBUG build queue test Notices, and the
test counter of handled events existed only to observe the old timing. None
of them is needed once one queue decides what is shown. This supersedes three
paragraphs under Visible Failures ("How Notices are handed over on screen",
"A Notice waits while another dialog on the Library screen is open", and "An
Import asked for while a Notice is showing"): the next dialog, including the
picker, now appears when the one before it closes, with no 150 ms pause.

## 2026-11-08: Reading

Opening a Book now shows its Pages one per screen. Terms used here: the *open
Book* is that screen; *chrome* is the Title, page counter, slider and Close
control that a tap shows or hides over the Page; a *push* is a screen added on
top of the Library inside the same window, so the Library stays underneath; a
*full-screen cover* is a screen SwiftUI (Apple's screen-building framework)
puts in a separate layer above the whole window; *log-only* means a failure is
written to the system log and the user sees nothing.

**Two failures while reading are log-only, by the owner's ruling.** Saving the
Reading Position when a Page is turned, and recording that a Book was opened.
The Page turn and the opening itself visibly worked, and a Notice would
interrupt reading for something the user cannot act on. The consequence the
owner accepted: if saves keep failing, the user finds out only at the next open
by landing on an older Page. Opening a Book the Library no longer has is the
one open failure that is shown: the Book cannot open and its Notice says so.
These are the only two places a failure is logged without a Notice, and each
carries a comment naming this ruling.

**Folio never reopens the Book that was open when it was last closed by the
system.** A fresh launch always lands in the Library; the Book shows its
Reading Position and sits first. If the app was not killed, backgrounding and
returning shows the same Page. Because the Reading Position is saved on every
Page turn and not on close, a kill loses nothing. Less state to keep right,
and the owner prefers the Library.

**Notices are presented at the root of the window, so the open Book is a push,
not a full-screen cover.** Every dialog and the status line now live in
`LibraryWindow`, the view that owns the window's navigation stack. Every screen
the stack shows, now and later, is beneath them, so a Notice appears over
whichever screen is on top. What the user experiences: an Import that fails
while they read shows its Notice over the Page instead of waiting until they
close the Book. SwiftUI puts a full-screen cover in a layer above the window's
root, where a root-level Notice could not appear, so the Book is pushed on
every platform. On iPhone the system back swipe from the left edge is off while
reading, because the left edge turns a Page; Close is the way out.

**The open Book belongs to its window on Mac.** Opening a Book in one window
changes nothing in another. A never-read Book gets its Reading Position set to
the first Page as soon as it opens, so looking at Page 1 and closing leaves
"Page 1 of N" on its card. "Open" on Mac is double-click or Return.

**Zoom is 2.5 times, from pinch or double tap, about the centre of the Page.**
A second double tap returns to fit. A pinch goes up to 5 times. Pages are
decoded at the window's size, as the design says, so a zoomed Page is
enlarged rather than redrawn and looks soft; raising the decode size by the
zoom scale would sharpen it at the cost of memory.

**Pages are paged by a horizontal scroll view; no UIKit or AppKit was needed.**
One SwiftUI mechanism (`ScrollView` with paging) turns Pages on iPhone, iPad and
Mac, and a zoomed Page pans inside its own scroll view and hands the swipe to
paging at its edge; both were checked on the iPhone simulator. Mac and iPad
were not checked by the builder. Hiding the back button turns off the iPhone
edge back swipe, so nothing was wrapped for that either.

**Where the controls sit.** Title and Close are in the toolbar the platform
draws (the navigation bar on iPhone and iPad, the window toolbar on Mac). The
counter and slider are one bar at the bottom of the Page on every platform,
because Mac has no bottom toolbar. On iPhone and iPad the whole chrome hides
until a tap; on Mac the toolbar stays and only the bottom bar hides.

**A Page file is at `<Book folder>/pages/<file name>`.** The design and plan
said `<Book folder>/<file name>`; every Page showed the "could not be shown"
placeholder until the real layout was used. The folder name now comes from the
import code (`ImportPipeline.pagesName`) so the reading code cannot drift from
it.

**A test hook for Notices was not added.** The plan proposed a debug-only
switch that queues test Notices. The Presentation Coordinator entry above
records that kind of hook as a removed workaround, so the Notice-over-the-open-
Book check used a real failing Import queued behind a long one.

## 2026-11-08: Xcode Cloud

*Xcode Cloud* is Apple's build service: when a commit reaches GitHub it builds,
tests and archives the app on Apple's machines, and can send the result to
TestFlight. An *archive* is the signed build that goes to TestFlight or the App
Store. A *workflow* is the list of when to run and what to do; it lives in App
Store Connect and is made in Xcode, not in this repository.

**Only Release is signed.** Signing (the team and certificate that prove a build
is yours) is set in `app/Config/Release.xcconfig` with the personal team
`PJBUF7JSHK`. Debug stays unsigned, so a machine with no Apple Developer account,
such as the GitHub Actions runner, can still build and test. Xcode's Signing pane
writes the team into `project.pbxproj` for every configuration, which would sign
Debug too; do not use it, and edit `Release.xcconfig` instead. What the user
experiences: nothing changes for a reader of the app; archives and TestFlight
builds are signed as the personal team.

**Xcode Cloud numbers its own builds.** TestFlight refuses a build number it has
already seen for a version, and `Version.xcconfig` holds a fixed 1.
`app/ci_scripts/ci_pre_xcodebuild.sh` (the folder Xcode Cloud reads, next to the
project) writes Xcode Cloud's build number into that file for archives only, on
the runner's copy of the code. The marketing version is still edited by hand.

**FolioCore's warnings still fail the build in Xcode Cloud.** Xcode silences
warnings in Swift packages, so the scheme's own tests would pass with a warning in
`FolioCore`. The same script runs `swift test` with warnings as errors before
Xcode Cloud builds for testing, as `scripts/test.sh` does.

**Left to the owner.** The workflow itself; the export-compliance answer
(whether the app uses non-exempt encryption), which TestFlight asks for each build
unless it is declared; and a macOS app category, which the Mac App Store
requires. GitHub Actions is unchanged and runs alongside.

## 2026-11-09: Reading Mode

A Book can now be read in either of two Reading Modes: Page by Page, as before,
or Vertical. Terms used here: the *strip* is what Vertical shows, every Page of
the Book placed under the one before it at the screen's width, touching, in one
column the reader scrolls; *decoding* is turning a Page's stored data into
pixels the screen can show; the *chrome* is the Title, counter, slider, Close
and Reading Mode controls that a tap shows or hides; *log-only* means a failure
is written to the system log and the user sees nothing. Every other mechanism is
defined in the paragraph that introduces it. The record of the work, with
Apple's text for every behaviour relied on, the measurements and the owner's
check list, is `docs/logs/2026-11-09-02-reading-mode-implementation.md`.

**Each Book remembers its own Reading Mode, and there is no Library-wide
default.** The owner wants the choice remembered, not made each time or guessed
from the Book, and remembering it per Book works the way the Reading Position
already does. A Library-wide default, or a setting to change one, was left out
of this slice. What the user experiences: choosing Vertical in a Book changes
only that Book; closing and reopening it, or relaunching Folio, opens it in
Vertical at its Reading Position's Page. A Book that has never been switched
reads Page by Page, and so does every Book already in the Library. The Library
card does not show the Reading Mode.

**A newly imported Book starts Vertical (2026-11-11).** The owner asked for
Vertical as the Reading Mode every Book starts in. Books already in a Library
have Page by Page saved on them, and nothing saved tells a Book whose reader
picked Page by Page from one that never switched, so the owner ruled that only
Books imported from now on start Vertical. What the user experiences: a Book
imported with this version opens as one strip; every Book imported before it
keeps reading the way it did until the reader switches it; the choice is still
remembered per Book, and there is still no setting for it. Rejected: switching
every existing Book to Vertical once, which would also have switched Books the
reader had deliberately kept Page by Page.

**In Vertical, the Page you are "on" is the Page at the top of the screen.**
Exactly: the last Page whose top edge has reached the top of the screen, where a
top exactly at the top counts; when the strip is scrolled to its very end, the
last Page, wherever its top is; when it is pulled down past its start, the first
Page. That Page is what the counter shows, what is saved as the Reading Position
and shown on the Library card, and what switching Reading Mode carries across.
The design first used the Page under the middle of the screen. The builder's
check found that, with Pages shorter than half the screen, it fights the way a
jump works: a jump puts the Page's top at the top of the screen, and the middle
is then on a later Page. So a jump showed a different Page than the one asked
for, the slider sprang forward, switching lost your place, and the last Page
could never be reached. The owner accepted the top rule. What the user
experiences: a Book whose Pages are all short opens on its Reading Position's
Page, and "Page N of N" is reachable.

**Only the reader's own scrolling moves the Reading Position in Vertical.**
Apple's scroll views report a *scroll phase*, a name for what the scroll view is
doing at each moment: dragged by the reader, coasting after the reader lets go,
moved by the app, touched by a finger that has not moved yet, or still. The
strip changes the Page being read only while the phase is dragging or coasting.
Opening the Book, switching Reading Mode, the slider and the Mac's left and
right arrow keys move the strip to a Page directly, and the scroll view's own
reports while it is being put in place never change the Page.

Why: the scroll view reports where it is once when the strip first appears,
before the strip has been moved to the Reading Position's Page. Apple does not
document that report, and while it counted as reading it saved Page 1 over the
Reading Position every time a Book opened in Vertical. Ignoring "the first
report" would be a guess about undocumented behaviour; the scroll phase is
documented. A finger resting on the screen does not count either, since Apple
describes that phase as one where "the user hasn't started a scroll", so a tap
never changes the Page.

What the user experiences: the counter follows their scrolling, and opening a
Book or switching Reading Mode never moves their place. Two consequences:

- After a jump to a Page near the end of a Book whose top cannot reach the top
  of the screen (the strip stops at its bottom first), the counter and the
  Reading Position keep the Page asked for, although the end-of-strip rule would
  say the last Page. The reader's next scroll applies the rule again.
- Apple does not say which phase the Mac's mouse wheel, trackpad or keyboard
  scrolling reports. If one of them does not count as the reader scrolling,
  scrolling that way would not move the counter. Not checked.

**A Book that fits on one screen does not bounce.** A *bounce* is the strip
giving under the finger when it is pulled past either end, and springing back
when let go. The top-of-the-screen rule reads the strip as at its very end
whenever the bottom of the last Page is on screen, which for a Book that fits on
one screen is true as soon as it is pulled at all. So one drag moved the counter
to the last Page and saved it, then saved the first Page again as the strip
sprang back. The strip now bounces top to bottom only when its Pages are taller
than the screen, and sideways only when zoomed, using the setting Apple
documents for this: the scroll view "bounces along the specified axis if the
size of the content exceeeds the size of the scrollable view in that axis"
(Apple's spelling). The top-of-the-screen rule stays as the design wrote it. What the user experiences:
a Book of one or two short Pages does not give under the finger and keeps its
Reading Position; a taller Book bounces as before. Seen on the iPhone simulator;
not checked on the Mac.

**Tall Pages are decoded at the screen's width, cut into slices, kept within a
memory budget, and decoded one at a time.** A *slice* is a horizontal band of a
decoded Page, at most 2,048 pixels tall; a *budget* is the most memory decoded
Pages may take. Some Pages are very tall and narrow (a continuous picture may be
800 by 12,000 pixels). Decoding such a Page to fit the window, as Page by Page
does, makes it blurry once it is stretched to the screen's width. Decoding it
whole at the screen's width makes it tens of megabytes and taller than some
graphics hardware can show as one picture. Folio does what the open-source
reader Mihon (Android) does; Aidoku (iOS) does the first step the same way.

- *Width.* A Page is decoded at the smaller of its own width and the screen's
  width in pixels, so never wider than its own pixels. The width is lowered
  further if the Page would not fit its share of the budget.
- *Slices.* The strip shows a Page's slices edge to edge, so the reader sees one
  Page, and the whole decoded Page is let go once its slices exist. Each slice
  is copied into memory of its own rather than cut as a window onto the whole
  Page, because Apple documents that a cut piece "retains a reference to the
  original image", which would keep the whole Page in memory behind its slices.
- *Budget.* The budget is 96 MB for one Page on iPhone and iPad and 256 MB on
  the Mac, and three times that for all the Pages held at once (288 MB and 768
  MB). After every single Page it decodes, the app lets go of the Pages it used
  least recently until it is back within the budget, but never the Page at the
  top of the screen or the one after it. The plan applied the budget only after
  decoding a group of Pages, which after a jump could briefly hold about seven
  Pages' worth; the design's "memory stays within a stated budget" decided
  against it.
- *Which Pages.* Only Pages with some part on screen, plus one more on each
  side, are decoded; that is more Pages when they are short. The strip asks for
  each of them itself; its cache does not decode ahead on its own. Which Pages
  these are is worked out again whenever the strip moves and whenever its width
  or zoom changes. A zoom out at the very top of the strip does not move it, so
  before the final review the Pages that came into view there stayed blank until
  the reader scrolled.
- *One at a time.* The strip keeps one cache of decoded Pages for as long as it
  is on screen, and every decode goes through it one after another, so two tall
  Pages are never decoded at once. When the strip's width changes, for example
  while a Mac window is being resized, the cache lets go of every Page it holds
  and decodes at the new width from then on. Until the final review a new cache
  was made for every new width, and a decode still running in the old one could
  overlap one in the new. Resizing is not checked on the Mac; it is on the
  owner's list.

What the reader would notice: tall Pages are sharp; a Page that left the screen
and comes back may be blank for a moment while it is decoded again. Two limits
are not exact:

- On the Mac a very wide and tall Page can come out up to 0.2% over 256 MB,
  because the system pads each row of pixels by an amount Apple does not
  document.
- While a Page is being cut into slices, its whole decoded picture and its
  slices can both be in memory for that moment, and the budget does not count
  it.

Page by Page is unchanged. The measured sizes are in the implementation log;
none was measured on a device.

**Page heights in the strip are fixed from each Page's pixel size before
anything is decoded.** A Page's *pixel size*, its width and height in pixels, is
read from the start of its stored data without decoding it. Every Page's height
at the strip's width is worked out from it before the strip appears, so the
strip never jumps under the reader's finger as Pages decode, and a jump to a
Page lands exactly on its top. A Page whose size cannot be read, because its
data is not a picture, takes a square the strip's width and shows the existing
placeholder for a Page that could not be shown. The plan first showed every Page
as a square and corrected the heights once the sizes arrived. That moves Pages
under the reader, so the strip now appears only once every size has been read.
What the user experiences: a blank moment when a Book opens in Vertical,
measured on the simulator at 0.01 to 0.02 s for 24 Pages and 0.06 to 0.22 s for
1,000 Pages.

**The strip is a plain stack, not a lazy one.** Each Page in the strip has a
*row*, the space kept for it on screen at that Page's height. A *plain stack*
places every row before anything is shown; a *lazy stack* places each row only
as it comes near the screen, to save work in long lists. Apple says lazy stacks
"trade some degree of layout correctness for performance" and advises to "always
start with a standard stack view". With the plan's lazy stack, a long jump on
the simulator put Pages far from where their known heights say they are: the
counter read Page 24 with Page 20 on screen, and a jump to Page 21 landed at the
end. The plain stack placed every Page exactly. In a plain stack every row is
made at once, so a row being made cannot be the signal to decode its Page; the
rule above (the Pages on screen plus one each side) decides instead. Cost: in a
Book of thousands of Pages an empty row is made for every Page when the Book
opens, so opening and scrolling could be slower on an older device than with a
lazy stack. Apple says to measure that on a device, not the simulator, and it
has not been measured on a device.

**Page heights are rounded to whole screen pixels.** SwiftUI (Apple's
screen-building framework) measures the screen in *points*; an iPhone has 3
pixels per point, most Macs 2. The *pixel grid* is the screen's own pixels. On
the simulator a scroll view was seen to come to rest only on whole pixels; this
is observed, and Apple does not document it. A Page's exact height can end
between two pixels. When it did, a jump to that Page could stop a fraction of a
point above its top. The strip then took the Page before it to be at the top, so
a jump back to that earlier Page did nothing: the counter read the earlier Page
while the later one was still on screen. Every Page's height is now rounded to a
whole number of pixels, so every Page's top is on that grid, where the scroll
view was seen to stop. Cost: each Page is up to half a pixel taller or shorter
than its true proportions.

**Zoom in Vertical keeps the reader's place.** Zoom works on the whole strip. A
pinch zooms from *fit* (the Page filling the screen's width) up to 5 times; a
double tap zooms to 2.5 times and a second one returns to fit; a pinch to zoom
out stops at fit, so the strip is never narrower than the screen. On every zoom
step, and whenever the width changes (turning the device, resizing a Mac
window), the strip moves so that the same part of the Page at the top stays
under the top of the screen: the same fraction of the way down that Page. The
plan jumped back to the Page's top instead, which made zooming in the middle of
a tall Page unusable. Across, the strip is put back in the middle on every zoom
step, so a reader who had panned to one side of a zoomed Page is brought back to
the middle when they pinch or double tap again. While the fingers pinch, the
strip is only drawn larger or smaller, about the top centre of the screen; it is
laid out at the new scale once, when the fingers lift. Laying it out on every
frame of the pinch made the scroll view report, for a moment, the new size with
a position from the old one, which deep in a Book dropped the Pages on screen
(a black flash on a real iPhone) and moved the Reading Position to a later Page
and back (reading-mode-implementation log, "Fix on a real iPhone").

The double tap zooms at once, without an animation. With the animation, a double
tap deep in the strip landed on another Page or a blank screen. Apple says the
scroll view "will clamp" a requested position "to only scroll to the size of its
actual content"; as far as can be told, during the animation the content was
still its unzoomed size. Without the animation it lands where it should. That is
observed on the simulator, not documented: Apple does not say when SwiftUI
applies the new size relative to the move. Switching Reading Mode resets the
zoom to fit.

**A failed Reading Mode save is log-only.** The switch itself visibly works on
screen, and a Notice would interrupt reading for something the reader cannot act
on; this follows the ruling for a failed Reading Position save. What the user
would notice: if the save fails, the Book opens next time in its previous
Reading Mode. The Reading entry above names two places where a failure is logged
without a Notice; this is the third, and its code carries a comment naming this
ruling.

**The saved Library moved to schema version 2.** The *store* is the file on the
device that holds the Library's saved data; its *schema* is the description of
how that data is laid out. Each version of the schema is kept as it was written,
and the app upgrades a store saved under an older version the first time it
opens it. Version 2 adds one optional field to a Book, its Reading Mode. Version
1 is now kept frozen, exactly as the previous version of the app saved data, as
the schema file asks. The upgrade is a *lightweight* one, where SwiftData
(Apple's storage framework) carries the data across itself, with no code of
ours; that it does so for this change is observed, as the limits below say. What
a version 1 store experiences: nothing visible. Every Book keeps its Pages,
Title, Cover and Reading Position, and reads Page by Page until the reader
chooses Vertical. A stored Reading Mode this version does not recognise, written
by a later version, also reads as Page by Page, so the Book still opens.
Evidence: a test writes a store with the frozen version 1 description, opens it
with version 2 and finds the Book unchanged, on the Mac and on the iOS
simulator. The limits of that evidence:

- Apple's pages fetched for this do not say that a lightweight upgrade covers an
  added optional field; that is observed.
- The test also passes with the upgrade step removed, so it shows that an old
  store opens, not that the step is what opens it.
- No store saved by an installed earlier build was tried.

**Not yet verified.** None of the following has been checked:

- **Everything on the Mac.** After an early attempt typed into another window,
  no agent was allowed to send keystrokes, clicks or pointer moves to the
  owner's Mac. So the toolbar control, the wheel, the trackpad, the arrow keys,
  Page Up and Page Down, Escape and window resizing are all unchecked.
- **Turning an iPhone or iPad while reading Vertical.** It is an animated size
  change, like the double tap was, and may land the reader on another Page.
- **Anything on an iPad.**
- **Anything on a real device**, including a pinch while moving the fingers, and
  smoothness and memory with 1,000 or more Pages. Every figure so far is from
  the iPhone simulator or the Mac.

The owner's check list is in the implementation log.

## 2026-11-11: Library Order

The reader can now choose how the Library's Books are ordered. Terms used here:
the *settings store* is the place Apple gives every app for small preferences;
the *Library's database* is the file on the device that already holds the Books
and Imports; a *database version* is the shape that file has, and the app
upgrades a file saved in an older shape the first time it opens it; a *record*
is one saved entry in that file. The reasoning that led here is in
`docs/logs/2026-11-11-01-library-order-design.md`; the record of the work, with
Apple's text for every behaviour relied on, what was seen on which simulator and
the owner's check list, is
`docs/logs/2026-11-11-02-library-order-implementation.md`.

**The Library Order is a Sort and a Direction, chosen separately.** The Sorts
are Recent, Title and Date Imported; the Directions are Ascending and
Descending. The owner wanted what Books are ordered by kept apart from which
way, so the menu is five choices that make six Library Orders, not six combined
choices, and picking another Sort keeps the Direction. What the user
experiences: in the Sort menu one Sort and one Direction are ticked at all
times; changing one never changes the other. A Library that has never been
given a choice is Recent, Descending, which is the order the Library always had,
so a reader who never opens the menu sees no change. Rejected: one list of
combined choices ("Title A to Z", "Title Z to A", and so on), and the words
"Name" and "Date Added", which the glossary rules out (Title; and "add" is not
used for an Import).

**The Library owns the Library Order and saves it in its own database; there is
one for the whole Library.** The Library already decides the order Books come in
and announces what changes, so the choice belongs with it, and not with one
screen. The settings store was considered, and the designer recommended it
because it needs no upgrade step; the owner chose the database so that
everything the Library remembers is in one file. The cost is a third database
version, which adds one record kind holding the Library Order, with at most one
record. The upgrade is lightweight, which means SwiftData (Apple's storage
framework) carries the saved data across itself with no code of ours; that it
does so for this change is observed in tests, and Apple's Core Data page on the
subject (Core Data is Apple's older database framework, which SwiftData is built
on; this is its page, not SwiftData's) is the closest support, a sentence about
adding, removing and renaming record kinds in a hierarchy. What a
user experiences: a Library saved by the previous version opens with every Book
in place and in Recent, Descending, and the choice survives quitting and
relaunching. On the Mac, two windows show the same Library Order, and choosing
in one reorders both. A saved Library Order this version does not recognise,
written by a later version, reads as Recent, Descending so the Library still
opens.

**What each Sort compares.** Recent: the time the Book was last opened, or the
time it was imported if it was never opened. Title: the Titles, compared the way
the Finder compares file names (ignoring capital letters and counting digits as
numbers by the device's language rules, so "Vol 2", "Vol 3", "Vol 10" come in
that order). Date Imported: the moment the Book's Import began copying Pages,
which every Book already stores. Books the Sort cannot tell apart (the same
Title, or the same time) are put in order by the time they were imported and
then by their identifier, so the grid never shuffles between loads, and
Descending is exactly the Ascending list read from the other end. What the user experiences: nothing a
reader does moves a Book under Date Imported; under Title a Book moves only
when it is renamed (it moves when the rename is saved) and a new Book appears at
its place by Title; under Recent a Book that was opened comes first (Descending)
or last (Ascending) the next time the Library screen appears, as it did before,
because the grid still does not reorder while a reader is tapping a Book. Imports
that have not produced a Book (Queued, In Progress or Failed) stay at the front
under every Library Order and both Directions. Three alternatives for Date
Imported were rejected: the moment the Import finished (the same order of Books,
and it would need a new stored time), the moment the Source was picked (differs
only for an Import that was retried, and it too needs a new stored time), and the
Source's own date on disk (a different idea, and a Book never refers to its
Source). Not checked: the Title comparison under any language but the one the
tests were run under, because Apple's page says the result "may be different
under different locales".

**A failed save of the Library Order leaves the grid as it was and shows a
Notice, unlike Reading Mode.** The Library saves first and announces the change
only afterwards, so when saving fails nothing on screen moves, the menu still
shows the old choice ticked, and a Notice titled "Couldn't Choose Library
Order" appears. A failed Reading Mode save is log-only (written to the system
log and not shown) because the switch visibly works on screen and a Notice
would interrupt reading; the owner agreed the stricter rule here, because a
grid that quietly goes back to its old order at the next launch is worse than
one that never moved. What the user experiences: a choice that looks made is
saved, or they are told it was not. Choosing the Library Order already in force
saves nothing and shows nothing.

**The Sort menu has no "Order" heading, and the Mac's View menu has a "Sort By"
submenu.** Screen copy uses glossary terms exactly, and the glossary avoids the
bare word "order" for a Direction (Pages already have a reading order). The
menu is therefore the three Sorts, a thin dividing line, then the two Directions,
with no heading on either group; the choices in force carry a tick. The
toolbar button is labelled "Sort" and drawn as up-and-down arrows. On the Mac the
same two groups are also under View → Sort By, because Apple's guidelines say
every toolbar item should also be a menu command, since a reader can hide or
change the toolbar. What the user experiences: nothing is drawn above either
group. Each group's control still carries a name for assistive tools such as
VoiceOver, hidden from view ("Sort" and "Direction"); Apple says a control
always needs a label even when it is hidden. What a screen reader says for the
menu was not checked.

The menu is dimmed while the Library has no Books, although Apple's guidelines
say a menu whose items are all unavailable should stay openable. What the user
experiences: with an empty Library the toolbar Sort cannot be opened. On the Mac
an empty Library therefore shows a dimmed toolbar Sort next to a live View →
Sort By, which is dimmed only when no Library window is in front. The owner
confirmed this on 2026-11-11 (implementation log, ruling 6).

**Not yet verified.** Everything on the Mac (agents send no input to the owner's
Mac, so the toolbar placement, View → Sort By, two windows, and the menus'
dimming are unchecked), what VoiceOver says, a failed save seen in the running
app (a test forces it and checks the Notice), the iPhone in landscape, iPad
split screen, and any real device. The owner's check list is in the
implementation log.

## 2026-11-11: Importing several Sources at once

The reader can now bring in several Sources in one go. Terms used here: the *file
picker* is the system screen Folio shows so the reader can choose Sources;
*ticking* is choosing a Source in that picker by tapping it, and the Open button
then confirms every ticked Source at once. The record of the work, with Apple's
text for every behaviour relied on, what was seen on which simulator and the
owner's check list, is `docs/logs/2026-11-11-03-import-several-sources.md`.

**Several Sources can be ticked or dropped at once, and each becomes its own
Import.** An Import is still one Source becoming one Book, so ticking ten zips
gives ten Import cards, the first In Progress and nine Queued, and ten Books
arriving one after another. Each is exactly what picking that Source alone would
have made. What the user experiences: on iPhone, iPad and Mac, tick several zips in
the file picker and press Open once; on the Mac, drop several folders and zips on
the Library window. Importing the same Source again still makes another Import and
another Book. There is no limit and no warning for many Sources.

**On iPhone and iPad the file picker ticks zips, never folders; a folder is picked
one at a time, as before.** A test build of the system picker on the iPhone 17 Pro
simulator (iOS 26.5) showed that tapping a folder opens it instead of ticking it,
and "Select All" ticks the zips and no folder. A folder is picked by going into it
and pressing Open, which delivers that one folder; with a zip ticked and a folder
then entered, Open delivered one of them, never both. The owner ruled: several zips
for now, folders as before, and no mixing. Folio does not enforce this. It imports
whatever the picker delivers, one Import each, so if a picker on another platform
hands over several folders, or folders with zips (the Mac's was not tried), each
still becomes its own Import. Refusing them would need a new Notice and new words on
screen for a case the owner did not ask to block.

**Picking one zip on iPhone now takes one more tap.** With several allowed, tapping
a zip ticks it and Open confirms; before, tapping a zip imported it at once. This
comes with the system picker and was reported to the owner with the test build's
findings.

**The order within one visit is whatever the picker delivers.** The Imports are
created one after another in that order, so they queue and run in it. The test build
delivered zips ticked A then B as B then A, and the owner ruled that the order need
not match the order ticked. Imports queue behind anything already Queued, as a
single new Import always did.

**A picked folder is still one Book made of its own Pages, and Folio does not look
inside it for zips.** Importing the zips found inside a folder was not asked for and
is a different idea: it would turn one Source into several Books, which an Import
never does.

**On the Mac, a drop holding anything that is not a folder or a zip is refused
whole.** What the user experiences: three zips and a folder dropped give four
Imports, in the drop's order; two zips and a PDF dropped spring back and nothing is
imported. Importing the zips and silently ignoring the PDF would leave the reader
unsure what happened, and a half-accepted drop is something the owner ruled out. An
empty drop is refused too. iPhone and iPad still have no drop target.

**Each failure keeps its own Notice, except that a Library that cannot save shows
one Notice for all of them.** A Source that cannot be referenced (it was removed, or
is not downloaded) gets its Notice naming it, and the Sources after it are still
imported. Ten ticked with three unreachable gives seven Import cards and three
Notices, each naming its Source, shown one after another as the reader closes each. A
Source whose Import fails later, say a zip with no images, ends Failed with its own
Notice when its turn comes, as it always did, and the rest carry on. The exception
is a Library that cannot save an Import at all, say because the disk is full: every
Source fails the same way, the Notice is "Couldn't Import" with a fixed message and
no Source name, and the rule that a Notice repeating the one before it shows once
means the reader sees one Notice and no Import cards. The owner accepted this: the
problem is the Library, not any one Source. Rejected: naming the Source in that
Notice (new words on screen, and ten identical dialogs) and stopping at the first
save failure (a failure then stops the rest, which the owner ruled out). The same
rule also means two Sources with the same name that fail the same way show one
Notice; that is today's rule, accepted.

**Nothing in FolioCore changed, and no words on screen changed.** The Library already
queues one Import per Source handed to it and runs them one at a time, in creation
order. The Import button, its Mac tooltip and File → Import… keep their copy. No
earlier entry in this file said the Mac drop takes one Source, so none needed
correcting; the code's own comments, which did, were updated.

**Not yet verified.** Everything on the Mac (agents send no input to the owner's
Mac, so the Mac's picker, File → Import…, dropping several, and a drop with a PDF
among zips springing back are unchecked), a real device, and the Import cards while
Imports are Queued (the small test zips finished too fast to catch them). The owner's
check list is in the implementation log.
