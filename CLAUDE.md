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

## Writing for the owner

Anything written for the project owner to decide on — rulings, summaries,
questions — is written in plain language. Glossary terms appear as they are;
every other term is either avoided or defined in the same sentence; the
consequence is stated as what a user would experience, not what the code does.

A mechanism that changes user-visible behaviour (how clean-up at launch works,
where temporary files go, what happens after a crash) gets a plain-language
definition before it is used in any ruling. That definition lives in the
decision log entry that introduces the mechanism, not in `CONTEXT.md`, which
stays a domain glossary.

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

## Library and Import code

`FolioCore` is organised by concern. `Domain/` holds the values (Book, Import,
Reading Position, Reading Mode), the Library events, the repository protocols,
and in-memory repositories for tests. `Source/` scans a folder Source into
ordered Pages, reads zips on Compression (`ZipArchive`, stored and deflate
only), and defines the `SourceAccess` port. `Import/` is the atomic
`ImportPipeline` (stage, copy Pages, render the Cover, move into place), Cover
rendering, and the storage capacity check. `Library/` is the `Library` actor
with its serial Import scheduler and launch recovery, the `LibraryItem` values
the grid shows, and `LibraryLog`.

The app target supplies the platform side. `Persistence/` holds the SwiftData
models and repositories, `LibraryStorage` (the backup-excluded Books directory
that also contains the store), and `FileSourceAccess` (security-scoped
bookmarks). `Library/` holds `LibraryModel` (the only consumer of the Library's
events) and the SwiftUI views, the Mac commands and drop target, and the iPad
selection bar. `LibraryWindow` is the root of each window: it owns the
navigation stack's path and every dialog and status line, so a Notice shows
over whichever screen is on top. `Reading/` holds the open Book: `ReadingView`
(hosts both Reading Modes, the Reading Mode control, the keys and the Reading
Position), `PageView` (zoom and the placeholder), `ReadingChrome` (counter and
slider), and `PageImage` / `PageImageCache` (pixel sizes read without decoding;
Page by Page's downsampled decoding, the current Page and one each side).
Vertical is `VerticalStripView`, one scroll view over a plain stack of Pages at
heights fixed before decoding, where only the reader's own scrolling moves the
Reading Position, and `SlicedPageCache`, an actor that decodes one Page at a
time at screen width and holds its slices within a byte budget. Their pure
rules, tested without a screen, are `StripGeometry` (heights on the pixel grid,
the Page at the top, which Pages to decode, keeping the place on zoom) and
`SlicedPage` (the decode width and the slicing).

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

Manual iOS checks need `SIMULATOR=<udid of a single-display iPhone>` (for
example `SIMULATOR=<udid> ./scripts/run.sh ios`): taps do not land on the
two-display "iPhone Duo" simulator the scripts pick by default.

`verify.sh` runs format → build → test → run (with a screenshot) for every
enabled platform. Set `SKIP_LAUNCH=1` to skip only the launch step — format,
build, and test still run for every platform. Used on headless CI, where
launching and screenshotting a simulator or app window is unreliable.

## Conventions

- **Swift Testing**, not XCTest. See `app/FolioTests/SmokeTests.swift`.
- **OSLog**, not `print`. Use `AppLog.general`, adding a category per subsystem;
  `AppLog.library` and `AppLog.persistence` cover the Library and SwiftData code.
- **SwiftUI** only; reach for UIKit/AppKit only when SwiftUI cannot do it, and
  record why in `DECISIONS.md`.
- User-facing strings go in `Localizable.xcstrings`. `xcodebuild` never writes
  the catalog, so sync it after adding strings, passing the stringsdata from
  both platforms (otherwise platform-only strings are marked stale):
  `xcrun xcstringstool sync app/Folio/Localizable.xcstrings --stringsdata <file> ...`
  using the `*.stringsdata` files under DerivedData (`Debug` and
  `Debug-iphonesimulator`). Restore compact `{}` entries afterwards so the diff
  shows only the new keys.
- Warnings are errors. Do not silence one without recording the reason.
- An action the user takes either visibly succeeds or visibly fails. A `catch`
  that only logs is a defect unless a comment at the site says why nothing the
  user sees depends on it. Every operation has a test that forces its failure
  and asserts the Notice.

## Documentation

- `CONTEXT.md` — the glossary; the only source of domain terms
- `DECISIONS.md` — why the project is set up this way
- `docs/superpowers/specs/` — feature designs
- `docs/logs/` — decision logs from `structured-commit`
