# Hardcover.app for KOReader

A KOReader plugin to update your [Hardcover.app](https://hardcover.app) reading status

## Installation

1. Copy `config.example.lua` to `config.lua`.
2. Fetch your API key from https://hardcover.app/account/api (just the part after `Bearer `)
3. Add your API key to config.lua
4. Install plugin by copying the entire folder to the KOReader plugins folder on your device

## Usage

The Hardcover plugin's menu can be found in the Bookmark top menu when a document is active.

### Linking a book

Before updates can be sent to Hardcover, the plugin needs to know which Hardcover book and/or edition your current document
represents.

You can search for a book by selecting `Link book` from the Hardcover menu. If any books can be found based
on your book's metadata, these will be displayed.

If you cannot find the book you're looking for, you can touch the magnifying glass icon in the upper left corner and
begin a manual search.

Selecting one of the presented books will link it to the current document.

Selecting a Hardcover book or edition will link it to your current document, but will not automatically update your
reading status on Hardcover. This can be done manually from the [update status](#updating-reading-status) menu, or using
the [track progress](#automatically-track-progress] option.

To clear the currently linked book, touch and hold to the `Link book` menu item for a moment.

After selecting a book, you can set a specific edition using the `Change edition` menu item. This will present a list
of available editions for the currently linked book.

### Updating reading status

To change your book status (Want To Read, Currently Reading, Read, Did Not Finish) on Hardcover, you open the
`Update status` menu after [linking your book](#linking-a-book). You can also remove the book from your Hardcover
library using the `Remove` menu item.

From this menu you can also update your current page and book rating, and add a new journal entry

Touch and hold the book rating menu item to clear your current rating.

### Add a journal entry quote

After selecting document text in a linked document, choose `Hardcover quote` from the highlight menu to display the
journal entry form, prefilled with the selected text and page.

### Automatically track progress

Automatic progress tracking is optional: book status and reading progress can instead be
[updated manually](#update-reading-status) from the `Update status` menu.

When track progress is enabled for a book which has been linked ([manually](#linking-a-book) or [automatically](#automatic-linking)),
page and status updates will automatically be sent to Hardcover for some reading events:

* Your current read will be updated when paging through the document, no more than once per minute. This frequency
[can be configured](#track-progress-frequency).
* When marking a book as finished from the file browser, the book will be marked as finished in Hardcover
* When reaching the end of the document, if the KOReader settings automatically mark the document as finished, the
book will be marked as finished in Hardcover. If the KOReader setting instead opens a popup, the book status will be checked
ten seconds later, and if the book has been marked finished, it will be marked as finish in Hardcover.

For all documents, but in particular for reflowable documents (like epubs), the current page in your reader may not
match that of the original published book.

Some documents contain information allowing the current page to map to the published book's pages. For these documents, 
the mapped page will be sent to Hardcover if possible.

For documents without these, your progress will be converted to a percentage of the number of pages in the original
published book, with a calculation like: 
`round((document_page_number / document_total_pages) * hardcover_edition_total_pages)`.

In both cases, this may not exactly match the page of the published document, and can even be far off if there
are large differences in the total pages.

#### Settings

##### Automatic linking

With automatic linking enabled, the plugin will attempt to find the matching book and/or edition on Hardcover
when a new document is opened, if no book has been linked already. These options are off by default.

* **Automatically link by ISBN**: If the document contains ISBN or ISBN13 metadata, try to find a matching edition for that ISBN
* **Automatically link by Hardcover**: If the document metadata contains a `hardcover` identifier (with a URL slug for the book)
  or a `hardcover-edition` with an edition ID, try to find the matching book or edition.
  (see: [RobBrazier/calibre-plugins](https://github.com/RobBrazier/calibre-plugins/tree/main/plugins/hardcover))
* **Automatically link by title**: If the document metadata contains a title, choose the first book returned from
hardcover search results for that title and document author (if available).
  
##### Track progress frequency

By default, no more than one update per minute will be sent to Hardcover for page turn events. If you don't need updates
this frequently, and to save battery, you can decrease this frequency further.

##### Always track progress by default

When always track progress is enabled, new documents will have the [track progress](#automatically-track-progress) option
enabled by automatically. You can still turn off `Track progress` on a per-document basis when this setting is enabled.

Books still must be linked (manually or automatically) to send updates to Hardcover.
