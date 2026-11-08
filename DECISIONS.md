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
as a UUID, which leaves the store files and the `.staging` area alone.

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
