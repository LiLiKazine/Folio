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

**App Sandbox is on**, with `com.apple.security.network.client`.
Retrofitting the sandbox is architectural — a path `String` stops being a valid
handle and persistence must move to security-scoped bookmarks — so it is cheaper
to start inside the container and add entitlements as needed. Sandbox network
denial presents as a generic connection failure rather than a permissions error,
which is why the network client entitlement ships from the start.

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
