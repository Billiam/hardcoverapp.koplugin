# Hardcover.app for KOReader

A KOReader plugin to update your [Hardcover.app](https://hardcover.app) book status

## Installation

1. Copy `config.example.lua` to `config.lua`.
2. Fetch your API key from https://hardcover.app/account/api (just the part after `Bearer `)
3. Add your API key to config.lua
4. Install plugin by copying the entire folder to the KOReader plugins folder on your device

## Usage

### Linking a book

Before updates can be sent to Hardcover, the plugin needs to know which Hardcover book and/or edition your current document
represents.

You can choose the book by selecting the `Link book` menu item from the Hardcover menu. If any books can be found based
on your book's metadata, these will be displayed.

To select a specific edition of this book, use the `Change edition` menu item to display a list of available editions
for the linked book.

Selecting a Hardcover book or edition will link it to your current document, but will does not automatically update your
reading status on Hardcover. This can be done manually from the [update status](#updating-reading-status) menu, or using
the [track progress](#track-progress-automatically] option.

To clear the currently linked book, touch and hold to the `Link book` menu item for a moment.

### Updating reading status

To change your book status (Want To Read, Currently Reading, Read, Did Not Finish) on Hardcover, you open the
`Update status` menu after [linking your book](#linking-a-book). You can also remove the book from your library using the
`Remove` option.

From this menu you can also update your current page and book rating, and add a new journal entry.

Touch and hold the book rating menu item to clear your current rating.

### Add a journal entry quote

After selecting document text in a linked document, choose `Hardcover quote` from the highlight menu to display the
journal entry form, prefilled with the selected text and page.

### Track progress automatically

Automatic progress tracking is optional: book status and reading progress can instead be
[updated manually](#update-reading-status) from the `Update status` menu.

When track progress is enabled for a book which has been linked (manually or automatically), page and status updates
will automatically be sent to Hardcover for some reading events:

* Your current read will be updated when paging through the document, no more than once per minute.
* When marking a book as finished from the file browser, the book will be marked as finished in Hardcover
* When reaching the end of the document, if the KOReader settings automatically mark the document as finished, the
book will be marked as finished in Hardcover. If the KOReader setting instead opens a popup, the book status will be checked
ten seconds later, and if the book has been marked finished, it will be marked as finish in Hardcover.

For all documents, but for reflowable documents (like epubs) in particular, the current page in your reader may not
match that of the original published book.

Some documents contain information allowing the current page to map to the published book's pages. For these documents, 
the mapped page will be sent to Hardcover if possible.

For documents without these, your progress will be converted to a percentage of the number of pages in the original
published book, with a calculation like: 
`round((document_page_number / document_total_pages) * hardcover_edition_total_pages)`.

In both cases, this may not exactly match the exact page of the published document, and can even be far off if there
are large differences in the total pages.

#### Settings

##### Automatic linking

With auto linking enabled, the plugin will attempt to find the matching book and/or edition on Hardcover
when a new document is opened, if no book has been linked already. These options are off by default.

* **Automatically link by ISBN**: If the document contains ISBN or ISBN13 metadata, try to find a matching edition for that ISBN
* **Automatically link by Hardcover**: If the document metadata contains a `hardcover` identifier (with a URL slug for the book)
  or a `hardcover-edition` with an edition ID, try to find the matching book or edition.
* **Automatically link by title**: If the document metadata contains a title, return the first book with a title _containing_ that title,
  preferring books with more readers and books with matching authors. This may or may not be the desired book, especially
  for uncommonly read books with short/common titles.
  
##### Always track progress

When always track progress is enabled, new documents will have the [track progress](#track-progress-automatically) option
enabled by default. You can still turn off `Track progress` on a per-document basis when this setting is enabled.

## Planned features

* Use search API instead of title search when matching books by title and author
* Enable manual search
