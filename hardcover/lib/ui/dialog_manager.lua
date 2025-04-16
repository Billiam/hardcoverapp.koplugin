local _ = require("gettext")
local json = require("json")

local UIManager = require("ui/uimanager")

local InfoMessage = require("ui/widget/infomessage")

local Api = require("hardcover/lib/hardcover_api")
local Book = require("hardcover/lib/book")
local User = require("hardcover/lib/user")

local HARDCOVER = require("hardcover/lib/constants/hardcover")

local JournalDialog = require("hardcover/lib/ui/journal_dialog")
local SearchDialog = require("hardcover/lib/ui/search_dialog")

local DialogManager = {}
DialogManager.__index = DialogManager

function DialogManager:new(o)
  return setmetatable(o or {}, self)
end

local function mapJournalData(data)
  local result = {
    book_id = data.book_id,
    event = data.event_type,
    entry = data.text,
    edition_id = data.edition_id,
    privacy_setting_id = data.privacy_setting_id,
    tags = json.util.InitArray({})
  }

  if #data.tags > 0 then
    for _, tag in ipairs(data.tags) do
      table.insert(result.tags, { category = HARDCOVER.CATEGORY.TAG, tag = tag, spoiler = false })
    end
  end
  if #data.hidden_tags > 0 then
    for _, tag in ipairs(data.hidden_tags) do
      table.insert(result.tags, { category = HARDCOVER.CATEGORY.TAG, tag = tag, spoiler = true })
    end
  end

  if data.page then
    result.metadata = {
      position = {
        type = "pages",
        value = data.page,
        possible = data.pages
      }
    }
  end

  return result
end

function DialogManager:buildSearchDialog(title, items, active_item, book_callback, search_callback, search)
  local callback = function(book)
    self.search_dialog:onClose()
    book_callback(book)
  end

  if self.search_dialog then
    self.search_dialog:free()
  end

  self.search_dialog = SearchDialog:new {
    compatibility_mode = self.settings:compatibilityMode(),
    title = title,
    items = items,
    active_item = active_item,
    select_book_cb = callback,
    search_callback = search_callback,
    search_value = search
  }

  UIManager:show(self.search_dialog)
end

function DialogManager:buildBookListDialog(title, items, icon_callback, disable_wifi_after)
  if self.search_dialog then
    self.search_dialog:free()
  end

  self.search_dialog = SearchDialog:new {
    compatibility_mode = self.settings:compatibilityMode(),
    title = title,
    items = items,
    left_icon_callback = icon_callback,
    left_icon = "cre.render.reload",
    close_callback = function()
      if disable_wifi_after then
        UIManager:nextTick(function()
          self.wifi:wifiDisablePrompt()
        end)
      end
    end
  }

  UIManager:show(self.search_dialog)
end

function DialogManager:updateSearchResults(search)
  local books, error = Api:findBooks(search, nil, User:getId())
  if error then
    if not Api.enabled then
      UIManager:close(self.search_dialog)
    end

    return
  end

  self.search_dialog:setItems(self.search_dialog.title, books, self.search_dialog.active_item)
  self.search_dialog.search_value = search
end

function DialogManager:updateRandomBooks(books)
  self.search_dialog:setItems(self.search_dialog.title, books)
end

function DialogManager:journalEntryForm(text, document, page, remote_pages, mapped_page, event_type)
  local settings = self.settings:readBookSettings(document.file) or {}
  local edition_id = settings.edition_id
  local edition_format = settings.edition_format

  if not edition_id then
    local edition = Api:findDefaultEdition(settings.book_id, User:getId())
    if edition then
      edition_id = edition.id
      edition_format = Book:editionFormatName(edition.edition_format, edition.reading_format_id)
      remote_pages = edition.pages
    end
  end

  mapped_page = mapped_page or self.page_mapper:getMappedPage(page, document:getPageCount(), remote_pages)
  local wifi_was_off = false
  local dialog
  dialog = JournalDialog:new {
    input = text,
    event_type = event_type or "note",
    book_id = settings.book_id,
    edition_id = edition_id,
    edition_format = edition_format,
    page = mapped_page,
    pages = remote_pages,
    save_dialog_callback = function(book_data)
      local api_data = mapJournalData(book_data)
      local result = Api:createJournalEntry(api_data)
      if result then
        UIManager:nextTick(function()
          UIManager:close(dialog)

          if wifi_was_off then
            UIManager:nextTick(function()
              self.wifi:wifiDisablePrompt()
            end)
          end
        end)

        return true, _(event_type .. " saved")
      else
        return false, _(event_type .. " could not be saved")
      end
    end,
    select_edition_callback = function()
      -- TODO: could be moved into child dialog but needs access to build dialog, which needs dialog again
      dialog:onCloseKeyboard()

      local editions = Api:findEditions(self.settings:getLinkedBookId(), User:getId())
      self:buildSearchDialog(
        "Select edition",
        editions,
        { edition_id = dialog.edition_id },
        function(edition)
          if not edition then
            return
          end

          dialog:setEdition(
            edition.edition_id,
            Book:editionFormatName(edition.edition_format, edition.reading_format_id),
            edition.pages
          )
        end
      )
    end,

    close_callback = function()
      if wifi_was_off then
        UIManager:nextTick(function()
          self.wifi:wifiDisablePrompt()
        end)
      end
    end
  }
  -- scroll to the bottom instead of overscroll displayed
  dialog._input_widget:scrollToBottom()

  self.wifi:wifiPrompt(function(wifi_enabled)
    wifi_was_off = wifi_enabled

    UIManager:show(dialog)
    dialog:onShowKeyboard()
  end)
end

function DialogManager:showError(err)
  UIManager:show(InfoMessage:new {
    text = err,
    icon = "notice-warning",
    timeout = 2
  })
end

return DialogManager
