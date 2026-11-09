# Folio

A local-first reader for ordered sets of images (comics, manga, scanned books,
art books, photo sets) that the user already has on their device. Everything
lives on the device; there is no account or network.

## Language

**Library**:
The user's Books, plus the Imports that have not yet produced one.
_Avoid_: collection, shelf, bookshelf

**Book**:
One readable unit in the Library, made of ordered Pages.
_Avoid_: comic, album, volume, gallery, document, item

**Page**:
One image in a Book, at a position in the Book's reading order. The order
belongs to the Book, so a later edition can change it.
_Avoid_: image, file, panel

**Source**:
The folder or zip the user picks in the file picker. An Import remembers its
Source; a Book never refers to one.
_Avoid_: original, file, archive

**Import**:
The record of turning one Source into one Book by copying its Pages into
Folio's own storage. It has a status: Queued, In Progress, Failed, or
Completed, and is kept after it ends. Imports run one at a time in creation
order; importing the same Source again makes another Import and another
Book; an Import found In Progress at launch returns to Queued.
_Avoid_: add, open, load, upload, task, job

**Title**:
A Book's display name. Defaults to the Source's own name.
_Avoid_: name, series

**Cover**:
The Page that represents a Book in the Library. For now always the first Page
in reading order.
_Avoid_: thumbnail

**Reading Position**:
The Page a reader was last on in a Book.
_Avoid_: progress, bookmark, last read

**Reading Mode**:
How a Book's Pages are laid out while reading. Page by Page shows one Page at
a time, turned by swiping; Vertical stacks every Page into one strip scrolled
top to bottom. A Book remembers its Reading Mode; a Book that has none reads
Page by Page.
_Avoid_: layout, view mode, scroll mode, webtoon

**Notice**:
A message the Library shows the user about an action that could not be
completed, naming what failed and, when the user can do something about it,
what to do.
_Avoid_: toast, alert, error message, banner

## Events

Facts the Library announces after they have happened. Named in the past
tense; each carries only terms from this glossary.

**ImportQueued**:
An Import was created from a Source, or a Failed one was retried, and is
waiting its turn.

**ImportStarted**:
A Queued Import has begun copying Pages and its total is known.

**ImportProgressed**:
An Import has copied more Pages; carries Pages done and total.

**ImportCompleted**:
An Import has ended with a new Book in the Library.

**ImportFailed**:
An Import has stopped without a Book, with a reason the user can act on;
cancellation by the user is one such reason.

**ImportRemoved**:
A Failed Import was taken out of the Library by the user.
_Avoid_: dismissed

**BookRenamed**:
A Book's Title has changed.

**BookOpened**:
A Book was opened by the reader; the basis for Library order.

**ReadingPositionChanged**:
A Book's Reading Position moved to a Page because the reader turned to it.

**ReadingModeChanged**:
A Book's Reading Mode changed because the reader chose a different one.

**BookRemoved**:
A Book and all its Pages have left the Library.

**LibraryStorageFailed**:
The Library could not save or apply a change on the user's behalf; carries
what it was trying to do. What the user sees may now disagree with what is
stored.
