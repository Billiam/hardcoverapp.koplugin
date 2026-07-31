-- wrapper around hardcover_api to add higher level methods
local _ = require("gettext")
local logger = require("logger")
local util = require("util")

local UIManager = require("ui/uimanager")

local Notification = require("ui/widget/notification")
local InfoMessage = require("ui/widget/infomessage")

local AladinApi = require("hardcover/lib/aladin_api")
local Api = require("hardcover/lib/hardcover_api")
local Book = require("hardcover/lib/book")
local BookSearch = require("hardcover/lib/book_search")
local User = require("hardcover/lib/user")

local SETTING = require("hardcover/lib/constants/settings")

local cache = {}

local Hardcover = {}
Hardcover.__index = Hardcover

function Hardcover:new(o)
  return setmetatable(o, self)
end

function Hardcover:showLinkBookDialog(force_search, link_callback)
  local search_value, books, err = self:findBookOptions(force_search)

  if err then
    logger.err(err)
    return
  end

  self.dialog_manager:buildSearchDialog(
    "Select book",
    books,
    {
      book_id = self.settings:getLinkedBookId()
    },
    function(book)
      self:linkBook(book)
      link_callback(book)
    end,
    function(search)
      self.dialog_manager:updateSearchResults(search, function(value)
        return self:findBooksByMetadata(value, nil, User:getId())
      end)
      return true
    end,
    search_value
  )
end

function Hardcover:cacheRandomBooks()
  local user_id = User:getId()

  local books, error = Api:getRandomToRead(user_id, 10)
  if error then
    UIManager:show(InfoMessage:new {
      text = _("Error fetching to-read list"),
      icon = "notice-warning",
      timeout = 2
    })
    return
  end

  cache.random_books = books
  return books
end

function Hardcover:showRandomBookDialog()
  self.wifi:wifiPrompt(function(wifi_enabled)
    local books = cache.random_books
    if not books then
      books = self:cacheRandomBooks()
    end

    if not cache.random_books or #cache.random_books == 0 then
      UIManager:show(Notification:new {
        text = "No books found on Want to Read list",
        timeout = 4
      })

      if wifi_enabled then
        UIManager:nextTick(function()
          self.wifi:wifiDisablePrompt()
        end)
      end

      return
    end

    self.dialog_manager:buildBookListDialog("Suggest a book", cache.random_books, function()
      books = self:cacheRandomBooks()
      if books then
        self.dialog_manager:updateRandomBooks(books)
      end
    end, wifi_enabled)
  end)
end

function Hardcover:updateCurrentBookStatus(status, privacy_setting_id)
  self.cache:updateBookStatus(self.ui.document.file, status, privacy_setting_id)
  if not self.state.book_status.id then
    self.dialog_manager:showError("Book status could not be updated")
  end
end

function Hardcover:changeBookVisibility(visibility)
  self.cache:cacheUserBook()

  if self.state.book_status.id then
    self:updateCurrentBookStatus(self.state.book_status.status_id, visibility)
  end
end

function Hardcover:linkBook(book)
  local filename = self.ui.document.file

  local delete = {}
  local clear_keys = { "book_id", "edition_id", "edition_format", "pages", "title" }
  for _, key in ipairs(clear_keys) do
    if book[key] == nil then
      table.insert(delete, key)
    end
  end

  local new_settings = {
    book_id = book.book_id,
    edition_id = book.edition_id,
    edition_format = Book:editionFormatName(book.edition_format, book.reading_format_id),
    pages = book.pages,
    title = book.title,
    _delete = delete
  }

  self.settings:updateBookSetting(filename, new_settings)
  self.cache:cacheUserBook()

  if book.book_id and self.state.book_status.id then
    if new_settings.edition_id and new_settings.edition_id ~= self.state.book_status.edition_id then
      -- update edition
      self.state.book_status = Api:updateUserBook(
        new_settings.book_id,
        self.state.book_status.status_id,
        self.state.book_status.privacy_setting_id,
        new_settings.edition_id
      ) or {}
    end
  end

  return true
end

function Hardcover:findBooksFromAladin(metadata, user_id)
  local items, err = AladinApi:search(
    metadata.normalized_title,
    metadata.normalized_author
  )
  if not items then
    return nil, err, metadata
  end

  local isbns = {}
  local items_by_isbn = {}
  for _, item in ipairs(items) do
    for _, isbn in ipairs({ item.isbn_13, item.isbn_10 }) do
      if isbn and not items_by_isbn[isbn] then
        items_by_isbn[isbn] = item
        table.insert(isbns, isbn)
      end
    end
  end

  metadata.aladin_result_count = #items
  local books, hardcover_err = Api:findBooksByIsbns(isbns, user_id)
  if not books then
    return nil, hardcover_err, metadata
  end

  for _, book in ipairs(books) do
    local item = items_by_isbn[book.isbn_13] or items_by_isbn[book.isbn_10]
    if item then
      book.aladin_link = item.link
      book.aladin_source = true
      book.aladin_title = item.title
    end
  end

  metadata.aladin_linked_count = #books
  return books, nil, metadata
end

-- could be moved to book search model
function Hardcover:findBooksByMetadata(title, author, user_id)
  local metadata = BookSearch:metadata(title, author)
  local results, err

  if metadata.is_korean and AladinApi:isConfigured() then
    return self:findBooksFromAladin(metadata, user_id)
  end

  if metadata.is_korean then
    results, err = Api:search(metadata.original_title, metadata.original_author, user_id)
  else
    -- Keep the existing search behavior unchanged for non-Korean metadata.
    results, err = Api:findBooks(metadata.original_title, metadata.original_author, user_id)
  end

  if err and (not metadata.is_korean or not metadata.normalized_changed) then
    return nil, err, metadata
  end

  results = results or {}
  if not metadata.is_korean then
    return results, nil, metadata
  end

  local original_match = BookSearch:findBestMatch(metadata, results)
  if not err and original_match then
    return results, nil, metadata
  end

  local normalized_results
  if metadata.normalized_changed then
    local normalized_err
    normalized_results, normalized_err = Api:search(
      metadata.normalized_title,
      metadata.normalized_author,
      user_id
    )

    if normalized_err then
      if #results > 0 then
        return results, nil, metadata
      end
      return nil, err or normalized_err, metadata
    end

    if normalized_results and #normalized_results > 0
      and BookSearch:findBestMatch(metadata, normalized_results)
    then
      return normalized_results, nil, metadata
    end
  end

  -- Hardcover often romanizes Korean authors in its search index. If both
  -- title/author queries miss, retry the normalized Korean title alone and
  -- still require the usual similarity check before automatic linking.
  local title_results, title_err = Api:search(
    metadata.normalized_title,
    nil,
    user_id
  )

  if title_results and #title_results > 0 then
    return title_results, nil, metadata
  end

  if title_err then
    if normalized_results and #normalized_results > 0 then
      return normalized_results, nil, metadata
    elseif #results > 0 then
      return results, nil, metadata
    end
    return nil, err or title_err, metadata
  end

  if normalized_results and #normalized_results > 0 then
    return normalized_results, nil, metadata
  end

  if err then
    return nil, err, metadata
  end

  return results, nil, metadata
end

function Hardcover:findBookOptions(force_search)
  local props = self.ui.document:getProps()
  local identifiers = Book:parseIdentifiers(props.identifiers)
  local user_id = User:getId()

  if not force_search then
    local book_lookup = Api:findBookByIdentifiers({
      isbn_10 = identifiers.isbn_10,
      isbn_13 = identifiers.isbn_13,
    }, user_id)
    if book_lookup then
      return nil, { book_lookup }
    end

    book_lookup = Api:findBookByIdentifiers({
      book_slug = identifiers.book_slug,
      edition_id = identifiers.edition_id,
    }, user_id)
    if book_lookup then
      return nil, { book_lookup }
    end
  end

  local title = props.title
  if not title or title == "" then
    local _dir, path = util.splitFilePathName(self.ui.document.file)
    local filename, _suffix = util.splitFileNameSuffix(path)

    title = filename:gsub("_", " ")
  end
  local result, err = self:findBooksByMetadata(title, props.authors, user_id)
  return title, result, err
end

function Hardcover:autolinkBook(book)
  if not book then
    return
  end

  local linked = self:linkBook(book)
  if linked then
    UIManager:show(Notification:new {
      text = _("Linked to: " .. book.title),
    })
  end
end

function Hardcover:linkBookByIsbn(identifiers)
  if identifiers.isbn_10 or identifiers.isbn_13 then
    local user_id = User:getId()
    local book_lookup = Api:findBookByIdentifiers({
      isbn_10 = identifiers.isbn_10,
      isbn_13 = identifiers.isbn_13
    },
      user_id
    )
    if book_lookup then
      self:autolinkBook(book_lookup)
      return true
    end
  end
end

function Hardcover:linkBookByHardcover(identifiers)
  if identifiers.book_slug or identifiers.edition_id then
    local user_id = User:getId()
    local book_lookup = Api:findBookByIdentifiers(
      { book_slug = identifiers.book_slug, edition_id = identifiers.edition_id }, user_id)
    if book_lookup then
      self:autolinkBook(book_lookup)
      return true
    end
  end
end

function Hardcover:linkBookByTitle()
  local props = self.ui.document:getProps()

  local results, _, metadata = self:findBooksByMetadata(props.title, props.authors, User:getId())
  local match = BookSearch:findBestMatch(metadata, results)
  if match then
    self:autolinkBook(match)
    return true
  end
end

function Hardcover:tryAutolink()
  if self.settings:bookLinked() then
    return
  end

  local props = self.ui.document:getProps()

  local identifiers = Book:parseIdentifiers(props.identifiers)
  if ((identifiers.isbn_10 or identifiers.isbn_13) and self.settings:readSetting(SETTING.LINK_BY_ISBN))
    or ((identifiers.book_slug or identifiers.edition_id) and self.settings:readSetting(SETTING.LINK_BY_HARDCOVER))
    or (props.title and self.settings:readSetting(SETTING.LINK_BY_TITLE)) then
    self.wifi:withWifi(function()
      self:_runAutolink(identifiers)
    end)
  end
end

function Hardcover:_runAutolink(identifiers)
  local linked = false
  if self.settings:readSetting(SETTING.LINK_BY_ISBN) then
    linked = self:linkBookByIsbn(identifiers)
  end

  if not linked and self.settings:readSetting(SETTING.LINK_BY_HARDCOVER) then
    linked = self:linkBookByHardcover(identifiers)
  end

  if not linked and self.settings:readSetting(SETTING.LINK_BY_TITLE) then
    self:linkBookByTitle()
  end
end

return Hardcover
