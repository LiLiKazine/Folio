# Folio

A local-first reader for folders and zips of images (comics, manga, scanned books, photo sets), fully offline on iPhone, iPad, and Mac.

For: People who already have comics or other image sets downloaded on their Apple devices and want to read them without any network or account.

## Glossary first

`CONTEXT.md` is the project's ubiquitous language. In designs, code, tests,
commit messages, and UI copy, use its terms exactly (Library, Book, Page,
Source, Import, Title, Cover, Reading Position) and never the words listed
under _Avoid_. Introducing a new domain concept, or changing the meaning of an
existing one, requires confirming with the project owner first; once agreed,
add it to `CONTEXT.md` before using it anywhere else.

## Architecture

SwiftUI app targeting iOS and macOS, bundle identifier `io.lilikaine.github.folio`.
Swift 6 language mode with strict concurrency; `async`/`await` and actors
rather than GCD or locks.

Build settings live in `app/Config/*.xcconfig` as text, not in the pbxproj.
`Shared.xcconfig` is the file to read or edit for language mode, platforms, and
signing. The Xcode project uses synchronized folder groups: a new `.swift` file
is added to the target by writing it into `app/Folio/` — no project file
edit is needed.

## Core package

`app/FolioCore/` is a standalone Swift package holding platform-agnostic
domain logic. It builds and tests without a simulator:

```bash
swift test --package-path app/FolioCore -Xswiftc -warnings-as-errors
```

`./scripts/test.sh` runs it first (with that flag), so a domain failure surfaces
before any simulator boots.

The package **is** linked into the app target, and
`app/Folio/FolioApp.swift` imports it — which is what keeps the link
honest: delete the package dependency and the app stops compiling, rather than the
link rotting behind a sentence in this file.

**Warnings-as-errors does not apply when Xcode builds the package.** Xcode compiles
package dependencies with `-suppress-warnings`, on the theory that warnings in
someone else's package are not actionable. That flag conflicts fatally with
`-warnings-as-errors`, so the manifest cannot declare it and `scripts/test.sh`
passes it instead. Practical consequence: a warning in `FolioCore` fails
`./scripts/test.sh` and CI, but is silently ignored when you build the app in
Xcode — so a clean Xcode build is not evidence the package is warning-free. Run the
script. `SWIFT_SUPPRESS_WARNINGS = NO` at the project level does not fix this;
Xcode applies the flag to package targets directly.

## Commands

Use these rather than raw `xcodebuild`; they are the stable interface.

```bash
./scripts/build.sh            # build every enabled platform
./scripts/test.sh             # run the test suite
./scripts/format.sh           # format in place (--check to verify only)
./scripts/run.sh              # build, install, launch
./scripts/verify.sh           # the full green gate
```

Any of build/test/run accepts a platform argument: `./scripts/test.sh macos`.

Every `xcodebuild` invocation writes its **full** output to `build/`:
`last-build.log`, `last-test.log`, `run-build-<platform>.log`. On failure the
script prints the tail and the log path; read the log rather than re-running with
more verbosity. `build/` is gitignored.

`build.sh` compiles Debug, matching the scheme's Run action. Set
`CONFIGURATION=Release` to compile the optimised configuration
(`app/Config/Release.xcconfig`) — worth doing before the first archive, since
nothing in the normal loop exercises it.

`verify.sh` runs format → build → test → run (with a screenshot) for every
enabled platform. Set `SKIP_LAUNCH=1` to skip only the launch step — format,
build, and test still run for every platform. Used on headless CI, where
launching and screenshotting a simulator or app window is unreliable.

## Conventions

- **Swift Testing**, not XCTest. See `app/FolioTests/SmokeTests.swift`.
- **OSLog**, not `print`. Use `AppLog.general`, adding a category per subsystem.
- **SwiftUI** only; reach for UIKit/AppKit only when SwiftUI cannot do it, and
  record why in `DECISIONS.md`.
- User-facing strings go in `Localizable.xcstrings`.
- Warnings are errors. Do not silence one without recording the reason.

## Documentation

- `CONTEXT.md` — the glossary; the only source of domain terms
- `DECISIONS.md` — why the project is set up this way
- `docs/superpowers/specs/` — feature designs
- `docs/logs/` — decision logs from `structured-commit`
