# Changelog

## Unreleased

### 🚀 Added

* Display edition language and series in book searches

### 🩹 Fixes

* Fix crash when navigating to previous page in search menu after images have loaded
* Fall back to less specific reading format when edition format is unavailable

### 🧹 Chores

* Renamed lib directory and config.lua to prevent conflicts with other plugins

### ⚠️ Upgrading

`config.lua` has been renamed to `hardcover_config.lua`. Make this change on your device!

## 0.0.7 (2024-12-30)

### 🚀 Added

* Added option to update books by percentage completed rather than timed updates
* Display error and disable some functionality when Hardcover API indicates that API key is not valid, in preparation
  for [upcoming API key reset](https://github.com/Billiam/hardcoverapp.koplugin/issues/6)
* Allow linking books, enabling/disabling book tracking from KOReader's gesture manager

### 🩹 Fixes

* Fix crash when linking book from hardcover menu
* Fix automatic book linking not working unless track progress (or always track progress) already set
* Fix manual and automatic book linking not working for hardcover identifiers
* Fix failure to mark book as read when end of book action displays a dialog
* Fix a crash when searching without an internet connection
* Fix page update tracking not working correctly when using "always track progress" setting
* Fix off-by-one page number issue when document contains a page map
* Fix unable to set edition if that edition already set in hardcover

### 🧹 Chores

* Update default edition selection in journal dialog to use multiple API calls instead of one due to upcoming Hardcover
  API limits
* Fetch book authors from cached column in Hardcover API

## 0.0.6 (2024-12-10)

### 🚀 Added

* Added compatibility mode with reduced detail in search dialog for incompatible versions of KOReader

### 🩹 Fixes

* Fix crash when selecting specific edition in journal dialog

## 0.0.5 (2024-12-04)

### 🩹 Fixes

* Fix failed identifier parsing by Hardcover slug
* Fix error when searching for books by Hardcover identifiers
* Fix note content not saving depending on last focused field
* Fix note failing to save without tags

## 0.0.4 (2024-12-01)

### 🩹 Fixes

* Fix error when sorting books in Hardcover search

## 0.0.3 (2024-11-29)

### 🩹 Fixes

* Fixed autolink failing for Hardcover identifiers and title
* Fixed autolink not displaying success notification

## 0.0.2 (2024-11-27)

### 🩹 Fixes

* Increased default tracking frequency to every 5 minutes
* Skip book data caching if not currently viewing a document
* Fix syntax error in suspense listener
* Only eager cache book data when book tracking enabled (for page updates)
* Fix errors when device resumed without an active document

## 0.0.1 (2024-11-24)

Initial release
