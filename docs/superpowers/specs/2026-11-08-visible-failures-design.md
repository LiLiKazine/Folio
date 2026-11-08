# Visible Failures — Design

Date: 2026-11-08
Status: ready for approval
Glossary: `CONTEXT.md` is authoritative. Capitalised terms are glossary terms.

## Intent

Today an action the user takes can fail without any sign on screen. The first
Import on a Mac did exactly that: picking a folder produced nothing, because
the failure happened before an Import record existed, and the code's answer to
every unexpected error was "log it and return". A log line is diagnostics for
the developers. It is not an outcome for the person holding the device.

This slice makes one principle hold everywhere: **an action the user takes
either visibly succeeds or visibly fails.** It changes how the Library reports
failure, what the screen does with those reports, and how the codebase is held
to the rule.

## Goals

- Every user-initiated operation (Import, Cancel, Retry, Remove an Import,
  Rename, Open, Remove a Book) has a defined failure presentation, and the
  app shows it whenever that operation fails, for any reason.
- Failures that happen inside the Library on the user's behalf but not in
  direct response to a tap (a record that could not be saved, a Book whose
  folder could not be deleted) are also presented, with wording that says what
  the user is now looking at.
- Catching an error without presenting it requires a written justification at
  the catch site.
- Each operation has a test that forces its failure and asserts the
  user-visible result.
- The rule holds identically on iPhone, iPad, and Mac. The Library, the
  model, and the Notice presentation are shared code; nothing in this slice
  is platform-specific, and the app test suite runs on both iOS and macOS.

## Non-goals

- Automatic retry of failed operations.
- Persisting Notices across launches.
- Crash reporting or any network telemetry.
- Changing what the reader slice will do; this slice only sets the rule it
  must follow.
- Fixing why Import fails on the Mac (signing, drag-and-drop).

## Anti-goals

- A `catch` that only logs. Logging stays, as diagnostics, but never as the
  sole response.
- Blaming the user for an internal failure. Wording distinguishes "the folder
  is gone" from "Folio couldn't save".
- A Notice the user cannot act on or dismiss.

## Glossary additions (confirmed by the owner, recorded in CONTEXT.md)

**Notice**: A message the Library shows the user about an action that could
not be completed, naming what failed and, when the user can do something
about it, what to do. Avoid: toast, alert, error message, banner.

**LibraryStorageFailed** (event): The Library could not save or apply a change
on the user's behalf; carries what it was trying to do. The user's view may
now disagree with what is stored.

## Domain model changes

### Typed, presentable errors

`LibraryError` becomes the only error type the Library's public operations
throw, and every case is presentable:

- `emptyTitle`
- `notFound` (the Book or Import is no longer in the Library)
- `invalidStatus` (for example Retry on an Import that is not Failed)
- `sourceUnavailable(sourceName)` — the picked folder or zip could not be
  referenced or opened
- `sourceNotDownloaded(sourceName)` (reserved for operations that open the
  Source; `createImport` only makes a bookmark and cannot hit it, so "not
  downloaded" reaches the user as a Failed Import, as today)
- `storage(operation)` — a repository or file-system write failed; `operation`
  names what was attempted in glossary terms

Anything else caught inside the Library is wrapped as `storage(operation)`
before it leaves the actor. The Library never throws a raw Foundation error.

### Failures without a caller

Failures inside the scheduler and launch recovery have no caller to throw to.
They emit `LibraryStorageFailed(operation)` on the event stream instead of
only logging. Specifically:

- a Failed status that could not be written after a retry → operation
  `Import`
- a queue fetch that failed (the queue is stalled until the next change) →
  `Update the Library`
- a Book record that could not be removed when its folder is missing (a half
  Book is now visible) → `Update the Library`
- the Books folder could not be listed or the Book records could not be read
  while checking each Book still has its folder at launch (a half Book may stay
  visible) → `Update the Library`
- a Book folder that could not be deleted after its record was removed →
  `Delete Book`
- the Library failing to start (`Library.start()` threw before recovery) →
  `Open the Library`
- a reload of the Library's items failing in the model → `Update the Library`

Best-effort cleanup of temporary files stays log-only, with a comment saying
why: nothing the user sees depends on it.

### What the user sees

The model turns every `LibraryError` and every `LibraryStorageFailed` event
into one Notice. Notices queue: a second failure does not overwrite the first.
The Notice is a system alert with one `OK` button, titled by the operation
and explained by the reason. Exact copy:

| Failure | Title | Message | Presentation |
|---|---|---|---|
| createImport, sourceUnavailable | `Couldn't Import “<Source>”` | `Folio couldn't open the folder or zip. Pick it again from the file picker.` | dialog |
| any op, storage | `Couldn't <Operation>` | `Folio couldn't save the change. Try again; if it keeps happening, relaunch Folio.` | dialog |
| rename, emptyTitle | `Couldn't Rename` | `A Book needs a Title.` | dialog |
| any op, notFound | `Couldn't <Operation>` | `It's no longer in the Library.` | dialog |
| any op, invalidStatus | `Couldn't <Operation>` | `That Import has already moved on.` | dialog |
| LibraryStorageFailed(operation) | `Couldn't <Operation>` | `Folio couldn't save the change. What you see may be out of date; relaunch Folio to refresh.` | status line |

Presentation: an action's Notice is a `dialog` (a system dialog the user must
close, shown because they just did something). A Notice about a background
failure, which no action of the user caused, is a `status line` (a small
message at the top of the Library with a Close control): the
LibraryStorageFailed row, `Open the Library`, and `Update the Library`. The
Import-failure Notice (an Import that was created and then failed) is a
`dialog`. Background Notices are shown as a status line per the Human
Interface Guidelines, which say "Avoid using an alert merely to provide
information" and "Avoid showing an alert when your app starts" (the
guidelines' own word "alert" is the dialog described here).

`<Operation>` values: `Import`, `Cancel Import`, `Retry Import`, `Remove
Import`, `Rename`, `Open`, `Delete Book`, `Update the Library`, `Open the
Library`. The `Open the Library` Notice reads: `Folio couldn't open its
Library. Relaunch Folio; if it keeps happening, free up storage.`

The existing Import failure alert (for an Import that was created and then
failed) is unchanged and becomes one kind of Notice.

## The failures that exposed the gap

Bookmark creation failing under ad-hoc signing, and dropped files arriving
without a sandbox grant, are not fixed here. This slice guarantees only that
when they happen, the user sees a Notice: `Couldn't Import “<Source>”` with
`Folio couldn't open the folder or zip. Pick it again from the file picker.`

## Rule for the codebase

Added to `CLAUDE.md` under Conventions:

> An action the user takes either visibly succeeds or visibly fails. A `catch`
> that only logs is a defect unless a comment at the site says why nothing the
> user sees depends on it. Every operation has a test that forces its failure
> and asserts the Notice.

## Tests

- For each public Library operation: a repository double that throws on the
  relevant write; assert the thrown `LibraryError` case.
- For each scheduler/recovery failure listed above: assert
  `LibraryStorageFailed` is emitted with the right operation.
- `LibraryModel`: for each operation, force the failure and assert the Notice
  title and message; assert two failures produce two Notices in order.
- `FileSourceAccess` failing to create a bookmark surfaces, through
  `createImport`, as a `sourceUnavailable` Notice (inject the failure).
- `LibraryModel`: `start()` failing yields the `Open the Library` Notice;
  `reload()` failing yields `Update the Library`.

## Left to the builder

- How Notices are queued and presented in SwiftUI (one alert at a time).
- The repository test doubles' shape.
- Whether `perform` in the model survives or each call maps its own error.
