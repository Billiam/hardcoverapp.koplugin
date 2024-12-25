local _ = require("gettext")
local json = require("json")

local UIManager = require("ui/uimanager")

local InfoMessage = require("ui/widget/infomessage")

local Api = require("lib/hardcover_api")
local User = require("lib/user")

local HARDCOVER = require("lib/constants/hardcover")

local JournalDialog = require("lib/ui/journal_dialog")
local SearchDialog = require("lib/ui/search_dialog")

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

function DialogManager:journalEntryForm(text, document, page, remote_pages, mapped_page, event_type)
  local settings = self.settings:readBookSettings(document.file) or {}
  local edition_id = settings.edition_id
  local edition_format = settings.edition_format

  if not edition_id then
    local edition = Api:findDefaultEdition(settings.book_id, User:getId())
    if edition then
      edition_id = edition.id
      edition_format = edition.format
      remote_pages = edition.pages
    end
  end

  mapped_page = mapped_page or self.page_mapper:getMappedPage(page, document:getPageCount(), remote_pages)

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
          if edition then
            dialog:setEdition(edition.edition_id, edition.edition_format, edition.pages)
          end
        end
      )
    end
  }
  -- scroll to the bottom instead of overscroll displayed
  dialog._input_widget:scrollToBottom()

  UIManager:show(dialog)
  dialog:onShowKeyboard()
end

function DialogManager:showError(err)
  UIManager:show(InfoMessage:new {
    text = err,
    icon = "notice-warning",
    timeout = 2
  })
end

return DialogManager
