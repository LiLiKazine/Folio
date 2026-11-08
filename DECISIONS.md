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

