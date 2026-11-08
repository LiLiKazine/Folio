# Folio

A local-first reader for folders and zips of images (comics, manga, scanned books, photo sets), fully offline on iPhone, iPad, and Mac.

## Requirements

- A recent Xcode with Swift 6.2+ tools (this project's CI runs on macos-26, defaulting to Xcode 26.5)
- iOS and macOS

## Getting started

```bash
./scripts/verify.sh    # build, test, and launch — confirms the checkout is green
open app/Folio.xcodeproj
```

## Layout

| Path | What |
|---|---|
| `app/Folio/` | App sources (synchronized folder — add files freely) |
| `app/FolioTests/` | Swift Testing suite |
| `app/Config/` | Build settings as xcconfig |
| `scripts/` | Build, test, format, run, verify |
| `docs/` | Specs and decision logs |

See `CLAUDE.md` for conventions and `DECISIONS.md` for why things are set up this way.
