# 2026-11-08-01: Project bootstrap

**Status:** Implemented

## Context

Folio starts from an empty directory holding only a design document for a
local-first comic reader. The project needed an Xcode project, build scripts,
tests, and an agent harness that proves itself green before any feature work.
The `bootstrap-apple-app` skill drove the interview and scaffolding.

## Options

| Approach | Pros | Cons |
|----------|------|------|
| Hand-made Xcode project, settings in pbxproj | Familiar | Settings invisible to text review; pbxproj edits on every new file |
| XcodeGen / Tuist | Declarative | Extra tool for a two-target project |
| Bootstrap skill template (chosen) | xcconfig settings, synchronized folders, scripts, green gate | Opinionated; needed two script fixes on this machine |

## Decision

Scaffold with the bootstrap skill: one multiplatform SwiftUI app target, one
test target, and an SPM core package, with settings in xcconfig and a
format/build/test/launch gate in `scripts/verify.sh`.

## Rationale

The interview answers (App Store, iOS and macOS, real domain logic in import
and zip handling, sandbox-compatible file access via the system picker) all
match the skill's defaults. The core package gives sub-second headless tests
for the import pipeline, which is where most of the first feature's logic lives.

## What Changed

- `app/Folio.xcodeproj`, `app/Folio/`, `app/FolioTests/`: app and test targets
- `app/FolioCore/`: SPM package linked into the app
- `app/Config/*.xcconfig`, `macOS.entitlements`: Swift 6, strict concurrency,
  warnings as errors, ad-hoc Mac signing, sandbox on
- `scripts/`: build, test, format, run, verify
- `.github/workflows/ci.yml`: CI running the gate with `SKIP_LAUNCH=1`
- `CLAUDE.md` (+ `AGENTS.md` symlink), `DECISIONS.md`, `README.md`
- `docs/superpowers/specs/2026-11-08-folio-comic-reader-design.md`: first
  feature design, written before bootstrap

## What Was Discovered

- The template's simulator resolver picks the last listed iPhone by name.
  This machine has two "iPhone Duo" simulators, and `xcodebuild` refuses an
  ambiguous name. Fixed by resolving to the UDID and passing `id=`.
- Pinning a uniquely named iOS 26.5 device ("iPhone 17 Pro") also failed:
  `xcodebuild` on Xcode 27.1 appends `OS:latest` to a name-only destination
  and found no match. UDID resolution sidesteps this too.
- "iPhone Duo" has two displays. `simctl io screenshot` fails with
  `NSPOSIXErrorDomain code=22` until `--display=N` is given. The error was
  invisible at first because it printed no command name; isolating it took
  stepping through boot, install, launch, and screenshot by hand. `run.sh`
  now retries on the primary display.
- The gate reported green on the first override run before these fixes, which
  shows a passing gate with a manual override is not the same as a passing
  gate. Both fixes are in the scripts, not in docs.
