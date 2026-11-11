# 2026-11-11-01: Library Order — design rulings

**Status:** Decided; not yet implemented

## Context

The Library shows Books in one order: the Book last opened, or imported if
never opened, comes first. The owner asked for more ways to order Books, "by
name, and by added time", then asked for the choice of what to order by to be
separate from the choice of which way. The design was walked through with the
glossary in hand: the words first, then who owns the choice, then concrete
cases, then how it is built. Design:
`docs/superpowers/specs/2026-11-11-library-order-design.md`. Plan:
`docs/superpowers/plans/2026-11-11-library-order.md`.

Terms used here: the *settings store* is the place Apple gives every app for
small preferences (UserDefaults); the *Library's database* is the file that
already holds the Books and Imports; a *database version* is the shape that
file has, which the app upgrades when the shape changes.

## Options

| Question | Chosen | Rejected and why |
|----------|--------|------------------|
| One list of combined rules, or two choices | Two: a Sort and a Direction | One list such as "Title A to Z, Title Z to A, …": the owner wanted what to order by kept apart from which way |
| The words | Library Order, made of a Sort (Recent, Title, Date Imported) and a Direction (Ascending, Descending) | "Name": the glossary says Title. "Date Added": the glossary avoids "add" for an Import. Bare "Order" for the Direction: Pages already have a reading order |
| Who owns the Library Order | The Library: it saves it and announces LibraryOrderChanged | The screen, sorting by a saved preference: the Library already decides the order today, and one choice for every window is a fact about the Library |
| Where it is saved | The Library's database, as one record (a third database version) | The settings store, the designer's recommendation (no upgrade step): the owner preferred everything in the database |
| What Date Imported is | The moment the Import began copying Pages, which every Book already stores | When the Import finished (same order of Books, needs a new stored time); when the Source was picked (differs only for a retried Import, needs a new stored time); the Source's own date on disk (a different idea, and a Book never refers to its Source) |
| A failed save | The grid keeps its order and a Notice appears | Switching on screen and only logging, as Reading Mode does: a grid that silently goes back at next launch is worse than one that never moved |
| Menu headings | None: three Sorts, a divider, two Directions; "Sort By" names the Mac's View-menu submenu | "Sort By" and "Order" headings, first offered by the designer: screen copy must use glossary terms, and the glossary avoids bare "order" for a Direction |

## Decision

The Library has a Library Order, a Sort and a Direction chosen separately,
starting as Recent, Descending; the Library owns it, saves it in its own
database and announces LibraryOrderChanged when the reader chooses another.

## Rationale

The Library already hands out Books in order and the glossary ties BookOpened
to that order, so the choice belongs with the Library and not with a screen.
Keeping the Sort and the Direction apart gives six orders from five menu
items and matches what the owner asked for. Starting at Recent, Descending
means a reader who never opens the menu sees no change.

## What Changed

- `CONTEXT.md`: new terms Library Order, Sort and Direction; new event
  LibraryOrderChanged; BookOpened is now "the basis for the Recent Sort".
- `docs/superpowers/specs/2026-11-11-library-order-design.md`: the design.
- `docs/superpowers/plans/2026-11-11-library-order.md`: the plan, five tasks.

## What Was Discovered

- A fresh reviewer read the design against the code as a builder would and
  had no questions left.
- The designer first told the owner the menu could be headed "Order". That
  broke the project's own rule that screen copy uses glossary terms, so the
  design drops the heading; the owner was told when the design was handed
  over.
- Opening a Book already does not reload the grid, so under Recent a Book
  moves to the front only the next time the Library screen appears. The
  design keeps that.
- Two Books with exactly the same time will be ordered by Date Imported and
  then by identifier in both Directions; today such ties go by identifier
  only. Nothing a reader sees depends on it.

## Commits

| Commit | Subject |
| --- | --- |
| (this) | docs(library): the Library Order glossary terms, design and plan |
