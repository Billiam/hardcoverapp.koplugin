# Changelog

## Unreleased

* Fix crash when linking book from hardcover menu

## 0.0.6 (2024-12-10)

### 🚀 Added

* Added compatibility mode with reduced detail in search dialog for incompatible versions of KOReader

### 🩹 Fixes

* Fix crash when selecting specific edition in journal dialog

## 0.0.5 (2024-12-04)

### 🩹 Fixes

* Fix failed identifier parsing by hardcover slug
* Fix error when searching for books by hardcover identifiers
* Fix note content not saving depending on last focused field
* Fix note failing to save without tags

## 0.0.4 (2024-12-01)

### 🩹 Fixes

* Fix error when sorting books in hardcover search

## 0.0.3 (2024-11-29)

### 🩹 Fixes

* Fixed autolink failing for hardcover identifiers and title
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
