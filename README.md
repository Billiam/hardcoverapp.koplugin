# Hardcover.app for KOReader

A KOReader plugin to update your [Hardcover.app](https://hardcover.app) reading status

## Installation

1. Copy `hardcover_config.example.lua` to `hardcover_config.lua`.
2. Fetch your API key from https://hardcover.app/account/api (just the part after `Bearer `)
3. Add your API key to `hardcover_config.lua`
4. Install plugin by copying the entire folder to the KOReader plugins folder on your device

## Usage

The Hardcover plugin's menu can be found in the Bookmark top menu when a document is active.

![Hardcover plugin main menu with the following menu items: the currently linked book (Frankenstein), an option to change the edition specific edition, a checkbox to Automatically track progress, Update status (which opens a submenu), Settings (which opens a submenu), and About](https://github.com/user-attachments/assets/0fd8f6fb-3a61-471f-9450-9a0b3dadc9d1)

### Linking a book

Before updates can be sent to Hardcover, the plugin needs to know which Hardcover book and/or edition your current
document represents.

You can search for a book by selecting `Link book` from the Hardcover menu. If any books can be found based
on your book's metadata, these will be displayed.

![A dismissable window titled "Select book" with a search button displayed as a magnifying glass in the upper left corner, and a close button on the right. A list of 14 possible books is displayed below this, with buttons to change result pages. The book title ande author are displayed if available, as well as the number of reads by hardcover users and the number of pages if available. Some books display cover images](https://github.com/user-attachments/assets/99d16ef0-6dda-41d8-bfdc-32c97ae09d87)

If you cannot find the book you're looking for, you can touch the magnifying glass icon in the upper left corner and
begin a manual search.

![An input dialog titled "New Search" with the text "Frankenstein Mary Shelley". Behind the dialog, a recent book search result dialog appears with two books](https://github.com/user-attachments/assets/73619448-9821-410a-901f-d8fc61185dd3)

Selecting a Hardcover book or edition will link it to your current document, but will not automatically update your
reading status on Hardcover. This can be done manually from the [update status](#updating-reading-status) menu, or using
the [track progress](#automatically-track-progress) option.

To clear the currently linked book, touch and hold to the `Linked book` menu item for a moment.

After selecting a book, you can set a specific edition using the `Change edition` menu item. This will present a list
of available editions for the currently linked book. No manual edition search is available

### Updating reading status

![A menu to update book status containing: a set of radio buttons for the current book status (Want to read, currently reading, read and did not finish), an item to unset the current status. The following section has an item to update the current page (displaying page 154 of 353), add a note, update rating (displaying the current rating of 4.5 stars), and an item to update the status privacy settings which open in a submenu](https://github.com/user-attachments/assets/55b33a0a-bda8-4ec9-918d-0409266abe3b)

To change your book status (Want To Read, Currently Reading, Read, Did Not Finish) on Hardcover, you open the
`Update status` menu after [linking your book](#linking-a-book). You can also remove the book from your Hardcover
library using the `Remove` menu item.

From this menu you can also update your current page and book rating, and add a new journal entry

Touch and hold the book rating menu item to clear your current rating.

### Add a journal entry quote

Selecting text to quote:

![Book text with two sentences highlighted. KOReader's highlight menu popup is displayed in the center with an option at the end for Hardcover quote](https://github.com/user-attachments/assets/5dba19a4-f72a-4894-820c-0cfdcc55bf68)

![A form window titled "Create journal entry". The previously selected text appears in an input field at the top. Below that is a toggle for whether the journal entry should be a note or a quote. A button to change the journal edition follows, and one to change the current page. Below those, a toggle to change the journal entry privay with the options Public, Follows and Private. Lastly are two input fields to set journal entry tags and spoiler tags respectively, and then buttons to save the entry or close the window](https://github.com/user-attachments/assets/c386f153-330f-4e1f-afa1-12fdf48a1216)

After selecting document text in a linked document, choose `Hardcover quote` from the highlight menu to display the
journal entry form, prefilled with the selected text and page.

### Automatically track progress

Automatic progress tracking is optional: book status and reading progress can instead be
[updated manually](#update-reading-status) from the `Update status` menu.

When track progress is enabled for a book which has been linked ([manually](#linking-a-book)
or [automatically](#automatic-linking)),
page and status updates will automatically be sent to Hardcover for some reading events:

* Your current read will be updated when paging through the document, no more than once per minute. This frequency
  [can be configured](#track-progress-frequency).
* When marking a book as finished from the file browser, the book will be marked as finished in Hardcover
* When reaching the end of the document, if the KOReader settings automatically mark the document as finished, the
  book will be marked as finished in Hardcover. If the KOReader setting instead opens a popup, the book status will be
  checked
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

## Settings

![A settings menu containing the following options: Checkboxes for Automatically link by ISBN, Automatically link by Hardcover identifiers and Automatically link by title and author. Below that is an item to change the Track progress frequency showing the current setting (1 minute), and a checkbox to Always track progress by default.](https://github.com/user-attachments/assets/dc8a397b-f36d-49da-b880-d04d47219ed0)

### Automatic linking

With automatic linking enabled, the plugin will attempt to find the matching book and/or edition on Hardcover
when a new document is opened, if no book has been linked already. These options are off by default.

* **Automatically link by ISBN**: If the document contains ISBN or ISBN13 metadata, try to find a matching edition for
  that ISBN
* **Automatically link by Hardcover**: If the document metadata contains a `hardcover` identifier (with a URL slug for
  the book)
  or a `hardcover-edition` with an edition ID, try to find the matching book or edition.
  (see: [RobBrazier/calibre-plugins](https://github.com/RobBrazier/calibre-plugins/tree/main/plugins/hardcover))
* **Automatically link by title**: If the document metadata contains a title, choose the first book returned from
  hardcover search results for that title and document author (if available).

### Track progress settings

By default, (when enabled) updates will be sent to hardcover at a frequency you can select, no more often than once per
minute. If you don't need updates this frequently, and to preserve battery, you can decrease this frequency further.

You can also choose to update based on your percentage progress through a book. With this option, an update will be sent
when you cross a percentage threshold (for examppe, every 10% completed).

### Always track progress by default

When always track progress is enabled, new documents will have the [track progress](#automatically-track-progress)
option
enabled by automatically. You can still turn off `Track progress` on a per-document basis when this setting is enabled.

Books still must be linked (manually or automatically) to send updates to Hardcover.

## Enable wifi on demand

On some devices, wifi can be enabled on demand without interruption. When this feature is enabled, wifi will be enabled
automatically before some types of background API requests (namely updating the initial application cache, and updating
your reading progress), and then disabled afterward.

This can improve battery life significantly on some devices, particularly with infrequent page updates.

This feature is not used for all network requests. If wifi has not been manually disabled the folling will not work:  

* fetching or updating your reading status manually
* adding a note or quote journal entry
* manually updating your reading progress from the menu

### Compatibility mode

When enabled, book and edition searches will be displayed in a simplified list with minimal data. This mode is the
default for KOReader versions prior to v2024.07
