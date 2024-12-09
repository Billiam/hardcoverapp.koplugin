local Api = require("hardcover_api")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")  -- luacheck:ignore
local DocSettings = require("docsettings")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local JournalDialog = require("journal_dialog")
local LuaSettings = require("frontend/luasettings")
local NetworkManager = require("ui/network/manager")
local Notification = require("ui/widget/notification")
local Scheduler = require("scheduler")
local SearchDialog = require("search_dialog")
local SpinWidget = require("ui/widget/spinwidget")
local T = require("ffi/util").template
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local https = require("ssl.https")
local json = require("json")
local logger = require("logger")
local ltn12 = require("ltn12")
local math = require("math")
local os = require("os")
local throttle = require("throttle")
local util = require("util")
local KoreaderVersion = require("version")

local VERSION = {0, 0, 5}
local RELEASE_API = "https://api.github.com/repos/billiam/hardcoverapp.koplugin/releases?per_page=1"

local HardcoverApp = WidgetContainer:extend {
  name = "hardcoverappsync",
  is_doc_only = false,
  state = nil,
  settings = nil,
  width = nil
}

local STATUS_TO_READ = 1
local STATUS_READING = 2
local STATUS_FINISHED = 3
local STATUS_DNF = 5

local PRIVACY_PUBLIC = 1
local PRIVACY_FOLLOWS = 2
local PRIVACY_PRIVATE = 3

local privacy_labels = {
  [PRIVACY_PUBLIC] = "Public",
  [PRIVACY_FOLLOWS] = "Follows",
  [PRIVACY_PRIVATE] = "Private"
}
-- nf-fa-book
local ICON_PHYSICAL_BOOK = "\u{F02D}"
-- nf-fa-tablet
local ICON_TABLET = "\u{F10A}"
-- nf-fa-headphones
local ICON_HEADPHONES = "\u{F025}"
-- nf-fa-bookmark_o
local ICON_BOOKMARK = "\u{f097}"
-- nf-fae-book_open_o
local ICON_OPEN_BOOK = "\u{E28B}"
-- nf-oct-check
local ICON_CHECKMARK = "\u{F42E}"
-- nf-fa-stop_circle
local ICON_STOP_CIRCLE = "\u{F28D}"
-- nf-fa-trash_can
local ICON_TRASH = "\u{F014}"
-- nf-fa-star
local ICON_STAR = "\u{F005}"
-- nf-fa-star_half
local ICON_HALF_STAR = "\u{F089}"

local SETTING_LINK_BY_ISBN = "link_by_isbn"
local SETTING_LINK_BY_HARDCOVER = "link_by_hardcover"
local SETTING_LINK_BY_TITLE = "link_by_title"
local SETTING_ALWAYS_SYNC = "always_sync"
local SETTING_COMPATIBILITY_MODE = "compatibility_mode"
local SETTING_USER_ID = "user_id"
local SETTING_TRACK_FREQUENCY = "track_frequency"

local HIGHLIGHT_MENU_NAME = "13_0_make_hardcover_highlight_item"

local CATEGORY_TAG = "Tag"

local function parseIdentifiers(identifiers)
  local result = {}

  if not identifiers then
    return result
  end

  -- TODO: are multiple identifiers comma/semicolon delimited?
  for line in identifiers:gmatch("%s*([^%s]+)%s*") do
    -- check for hardcover: and hardcover-edition:
    local hc = string.match(line, "hardcover:([%w_-]+)")
    if hc then
      result.book_slug = hc
    end

    local hc_edition = string.match(line, "hardcover%-edition:(%d+)")

    if hc_edition then
      result.edition_id = hc_edition
    end

    if not hc and not hc_edition then
      -- strip prefix
      local str = string.gsub(line, "^[^%s]+%s*:%s*", "")

      if str then
        local len = #str

        if len == 13 then
          result.isbn_13 = str
        elseif len == 10 then
          result.isbn_10 = str
        end
      end
    end
  end
  return result
end

local function showError(err)
  UIManager:show(InfoMessage:new{
    text = err,
    icon = "notice-warning",
    timeout = 2
  })
end

function HardcoverApp:onDispatcherRegisterActions()
  Dispatcher:registerAction("hardcover_link", { category = "none", event = "HardcoverLink", title = _("Hardcover Link"), general = true, })
end

function HardcoverApp:init()
  self.state = {
    page = nil,
    pos = nil,
    search_results = {},
    book_status = {},
    page_update_pending = false
  }
  --logger.warn("HARDCOVER app init")
  self.settings = LuaSettings:open(("%s/%s"):format(DataStorage:getSettingsDir(), "hardcoversync_settings.lua"))

  if KoreaderVersion:getNormalizedCurrentVersion() < 202407000000 then
    if self.settings:readSetting(SETTING_COMPATIBILITY_MODE) == nil then
      self:_updateSetting(SETTING_COMPATIBILITY_MODE, true)
    end
  end

  self:onDispatcherRegisterActions()
  self:initializePageUpdate()
  self.ui.menu:registerToMainMenu(self)
end

function HardcoverApp:_handlePageUpdate(filename, mapped_page, immediate)
  --logger.warn("HARDCOVER: Throttled page update")
  self.page_update_pending = false

  local book_settings = self:_readBookSettings(filename)
  if not book_settings.book_id or not book_settings.sync then
    return
  end

  if self.state.book_status.status_id ~= STATUS_READING then
    return
  end

  local reads = self.state.book_status.user_book_reads
  local current_read = reads and reads[#reads]
  if not current_read then
    return
  end

  local immediate_update = function()
    local result = Api:updatePage(current_read.id, current_read.edition_id, mapped_page, current_read.started_at)
    if result then

      self.state.book_status = result
    end
  end

  local trapped_update = function()
    Trapper:wrap(immediate_update)
  end

  if immediate then
    immediate_update()
  else
    UIManager:scheduleIn(1, trapped_update)
  end
end

function HardcoverApp:initializePageUpdate()
  local track_frequency = math.max(math.min(self:trackFrequency(), 120), 1)

  HardcoverApp._throttledHandlePageUpdate, HardcoverApp._cancelPageUpdate = throttle(track_frequency * 60, HardcoverApp._handlePageUpdate)
end

function HardcoverApp:changeTrackFrequency(time)
  self:_updateSetting(SETTING_TRACK_FREQUENCY, time)
  self:_cancelPageUpdate()
  self:initializePageUpdate()
end

function HardcoverApp:getMappedPage(raw_page, document_pages, remote_pages)
  local mapped_page = self.state.page_map and self.state.page_map[raw_page]

  if mapped_page then
    return mapped_page
  end

  if remote_pages and document_pages then
    return math.floor(( raw_page / document_pages) * remote_pages + 0.5)
  end

  return raw_page
end

function HardcoverApp:pageUpdateEvent(page)
  self.state.page = page
  if not (self.state.book_status.id and self:syncEnabled()) then
    return
  end

  --logger.warn("HARDCOVER page update event pending")
  local mapped_page = self:getMappedPage(page, self.ui.document:getPageCount(), self:pages())
  self:_throttledHandlePageUpdate(self.ui.document.file, mapped_page)
  self.page_update_pending = true
end

HardcoverApp.onPageUpdate = HardcoverApp.pageUpdateEvent
function HardcoverApp:onPosUpdate(_, page)
  if self.state.process_page_turns then
    self:pageUpdateEvent(page)
  end
end

function HardcoverApp:onUpdatePos()
  self:cachePageMap()
end

function HardcoverApp:onReaderReady()
  --logger.warn("HARDCOVER on ready")

  self:cachePageMap()
  self:registerHighlight()

  if self.ui.document and self:syncEnabled() then
    UIManager:scheduleIn(2, self.startReadCache, self)
  end
end

function HardcoverApp:onDocumentClose()
  UIManager:unschedule(self.startCacheRead)

  if self._cancelPageUpdate then
    self:_cancelPageUpdate()
  end

  if not self.state.book_status.id and not self:syncEnabled() then
    return
  end

  if self.page_update_pending then
    local mapped_page = self:getMappedPage(self.state.page, self.ui.document:getPageCount(), self:pages())
    self:_handlePageUpdate(self.ui.document.file, mapped_page, true)
  end

  self.process_page_turns = false
  self.page_update_pending = false
  self.state.book_status = {}
  self.state.page_map = nil
end

function HardcoverApp:onNetworkDisconnecting()
  --logger.warn("HARDCOVER on disconnecting")
  if self._cancelPageUpdate then
    self:_cancelPageUpdate()
  end

  Scheduler:clear()

  if self.page_update_pending and self.ui.document and self.state.book_status.id and self:syncEnabled() then
    local mapped_page = self:getMappedPage(self.state.page, self.ui.document:getPageCount(), self:pages())
    self:_handlePageUpdate(self.ui.document.file, mapped_page, true)
  end
  self.page_update_pending = false
end

function HardcoverApp:onNetworkConnected()
  --logger.warn("HARDCOVER on connected")
  if self.ui.document and self:syncEnabled() then
    self:startReadCache()
  end
end

function HardcoverApp:onEndOfBook()
  local file_path = self.ui.document.file
  local book_settings = self:_readBookSettings(file_path)

  if not book_settings.book_id or not book_settings.sync then
    return
  end

  local mark_read = false
  if G_reader_settings:isTrue("end_document_auto_mark") then
    mark_read = true
  end

  if not mark_read then
    local action = G_reader_settings:readSetting("end_document_action") or "pop-up"
    mark_read = action == "mark_read"

    if action == popup then
      mark_read = 'later'
    end
  end

  if not mark_read then
    return
  end

  local user_id = self:getUserId()

  local marker = function()
    local user_book = Api:findUserBook(book_settings.book_id, user_id) or {}
    self:updateBookStatus(file_path, STATUS_FINISHED, user_book.privacy_setting_id)
  end

  if mark_read == 'later' then
    UIManager:scheduleIn(15, function()
      local status = "reading"
      if DocSettings:hasSidecarFile(file_path) then
        local summary = DocSettings:open(file_path):readSetting("summary")
        if summary and summary.status and summary.status ~= "" then
          status = summary.status
        end
      end
      if status == "complete" then
        marker()
      end
    end)
  else
    marker()
    UIManager:show(InfoMessage:new {
      text = _("Hardcover status saved"),
      timeout = 2
    })
  end
end

function HardcoverApp:onDocSettingsItemsChanged(file, doc_settings)
  local book_settings = self:_readBookSettings(file)

  if not book_settings.book_id or not book_settings.sync then
    return
  end

  local status
  if doc_settings.summary.status == "complete" then
    status = STATUS_FINISHED
  elseif doc_settings.summary.status == "reading" then
    status = STATUS_READING
  end

  if status then
    local user_book = Api:findUserBook(book_settings.book_id, self:getUserId()) or {}
    self:updateBookStatus(file, status, user_book.privacy_setting_id)

    UIManager:show(InfoMessage:new {
      text = _("Hardcover status saved"),
      timeout = 2
    })
  end
end

function HardcoverApp:startReadCache()
  --logger.warn("HARDCOVER start read cache")
  if not self.ui.document then
    --logger.warn("HARDCOVER read cache fired outside of document")
    return
  end

  local cancel

  local restart = function()
    --logger.warn("HARDCOVER restart cache fetch")
    cancel()
    UIManager:scheduleIn(60, self.startReadCache, self)
  end

  cancel = Scheduler:withRetries(6, 3, function(success, fail)
    --logger.warn("Hardcover retry retrying")
    if not NetworkManager:isConnected() then
      return restart()
    end

    Trapper:wrap(function()
      local book_settings = self:_readBookSettings(self.ui.document.file)
      --logger.warn("HARDCOVER", book_settings)
      if book_settings and book_settings.book_id and not self.state.book_status.id then
        if self:syncEnabled() then
          local err = self:cacheUserBook()
          if err then
            --logger.warn("HARDCOVER cache error", err)
          end
          if err and err.completed == false then
            return fail(err)
          end
        end
      else
        self:tryAutolink()
      end
      --logger.warn("HARDCOVER Retry successful")
      success()
    end)
  end,

  function()
    --logger.warn("HARDCOVER enabling page turns")
    self.state.process_page_turns = true
  end,

  function()
    if NetworkManager:isConnected() then
      UIManager:show(Notification:new{
        text = _("Failed to fetch book information from Hardcover"),
      })
      self.connection_failed = true
    end
  end)
end

function HardcoverApp:registerHighlight()
  self.ui.highlight:removeFromHighlightDialog(HIGHLIGHT_MENU_NAME)

  if self:bookLinked() then
    self.ui.highlight:addToHighlightDialog(HIGHLIGHT_MENU_NAME, function(this)
      return {
        text_func = function()
          return _("Hardcover quote")
        end,
        callback = function()
          local selected_text = this.selected_text
          local raw_page = selected_text.pos0.page
          if not raw_page then
            raw_page = self.view.document:getPageFromXPointer(selected_text.pos0)
          end
          -- open journal dialog
          self:journalEntryForm(selected_text.text, raw_page, self.ui.document:getPageCount(), self:pages(), nil, "quote")

          this:onClose()
        end,
      }
    end)
  end
end

local function map_journal_data(data)
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
      table.insert(result.tags, { category = CATEGORY_TAG, tag = tag, spoiler = false })
    end
  end
  if #data.hidden_tags > 0 then
    for _, tag in ipairs(data.hidden_tags) do
      table.insert(result.tags, { category = CATEGORY_TAG, tag = tag, spoiler = true })
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

function HardcoverApp:journalEntryForm(text, page, document_pages, remote_pages, mapped_page, event_type)
  local settings = self:_readBookSettings(self.ui.document.file) or {}
  local edition_id = settings.edition_id
  local edition_format = settings.edition_format

  if not edition_id then
    local edition = Api:defaultEdition(settings.book_id, self:getUserId())
    if edition then
      edition_id = edition.id
      edition_format = edition.format
      remote_pages = edition.pages
    end
  end

  mapped_page = mapped_page or self:getMappedPage(page, document_pages, remote_pages)

  local dialog
  dialog = JournalDialog:new{
    input = text,
    event_type = event_type or "note",
    book_id = settings.book_id,
    edition_id = settings.edition_id,
    edition_format = settings.edition_format,
    page = mapped_page,
    pages = remote_pages,
    save_dialog_callback = function(book_data)
      local api_data = map_journal_data(book_data)
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

      local editions = Api:findEditions(self:getLinkedBookId(), self:getUserId())
      self:buildDialog(
        "Select edition",
        editions,
        { edition_id = dialog.edition_id },
        function(edition)
          if edition then
            dialog:setEdition(edition.edition_id, edition.edition_format, edition.pages)
          end
        end
      )
      UIManager:show(self.search_dialog)
    end
  }
  -- scroll to the bottom instead of overscroll displayed
  dialog._input_widget:scrollToBottom()

  UIManager:show(dialog)
  dialog:onShowKeyboard()
end

function HardcoverApp:_readBookSettings(filename)
  local books = self.settings:readSetting("books")
  if not books then return end

  return books[filename]
end

function HardcoverApp:_readBookSetting(filename, key)
  local settings = self:_readBookSettings(filename)
  if settings then
    return settings[key]
  end
end

function HardcoverApp:_updateBookSetting(filename, config)
  local books = self.settings:readSetting("books", {})
  if not books[filename] then
    books[filename] = {}
  end
  local book_setting = books[filename]

  for k,v in pairs(config) do
    if k == "_delete" then
      for _,name in ipairs(v) do
        book_setting[name] = nil
      end
    else
      book_setting[k] = v
    end
  end

  self.settings:flush()
end

function HardcoverApp:_updateSetting(key, value)
  self.settings:saveSetting(key, value)
  self.settings:flush()
end

function HardcoverApp:setSync(value)
  self:_updateBookSetting(self.ui.document.file, { sync = value == true })
  if value then
    if not self.state.book_status.id then
      self:startReadCache()
    end
  else
    if self._cancelPageUpdate then
      self:_cancelPageUpdate()
    end
    self.page_update_pending = false
  end
end

function HardcoverApp:editionLinked()
  return self:_readBookSetting(self.ui.document.file, "edition_id") ~= nil
end

function HardcoverApp:readLinked()
  return self:_readBookSetting(self.ui.document.file, "read_id") ~= nil
end

function HardcoverApp:bookLinked()
  return self:getLinkedBookId() ~= nil
end

function HardcoverApp:getLinkedTitle()
  return self:_readBookSetting(self.ui.document.file, "title")
end

function HardcoverApp:getLinkedBookId()
  return self:_readBookSetting(self.ui.document.file, "book_id")
end

function HardcoverApp:getLinkedEditionFormat()
  return self:_readBookSetting(self.ui.document.file, "edition_format")
end

function HardcoverApp:getLinkedEditionId()
  return self:_readBookSetting(self.ui.document.file, "edition_id")
end

function HardcoverApp:syncEnabled()
  local sync_value = self:_readBookSetting(self.ui.document.file, "sync")
  if sync_value == nil then
    sync_value = self.settings:readSetting(SETTING_ALWAYS_SYNC)
  end
  return sync_value == true
end

function HardcoverApp:pages()
  return self:_readBookSetting(self.ui.document.file, "pages")
end

function HardcoverApp:trackFrequency()
  return self.settings:readSetting(SETTING_TRACK_FREQUENCY) or 5
end

function HardcoverApp:compatibilityMode()
  return self.settings:readSetting(SETTING_COMPATIBILITY_MODE) == true
end

function HardcoverApp:linkBook(book)
  local filename = self.ui.document.file

  local delete = {}
  local clear_keys = {"book_id", "edition_id", "edition_format", "pages", "title"}
  for _,key in ipairs(clear_keys) do
    if book[key] == nil then
      table.insert(delete, key)
    end
  end

  local new_settings = {
    book_id = book.book_id,
    edition_id = book.edition_id,
    edition_format = book.edition_format,
    pages = book.pages,
    title = book.title,
    _delete = delete
  }

  if self.state.book_status.book_id == new_settings.book_id and self.state.book_status.edition_id == new_settings.edition_id then
    return
  end

  self:_updateBookSetting(filename, new_settings)

  self:cacheUserBook()
  self:registerHighlight()

  if book.book_id and self.state.book_status.id then
    if new_settings.edition_id and new_settings.edition_id ~= self.state.book_status.edition_id then
      -- update edition
      self.state.book_status = Api:updateUserBook(new_settings.book_id, self.state.book_status.status_id, self.state.book_status.privacy_setting_id, new_settings.edition_id) or {}
    end
  end

  return true
end


function HardcoverApp:autolinkBook(book)
  if not book then
    return
  end

  local linked = self:linkBook(book)
  if linked then
    UIManager:show(Notification:new{
      text = _("Linked to: " .. book.title),
    })
  end
end

function HardcoverApp:linkBookByIsbn()
  local props = self.view.document:getProps()

  local identifiers = parseIdentifiers(props.identifiers)
  if identifiers.isbn_10 or identifiers.isbn_13 then
    local user_id = self:getUserId()
    local book_lookup = Api:findBookByIdentifiers({ isbn_10 = identifiers.isbn_10, isbn_13 = identifiers.isbn_13 }, user_id)
    if book_lookup then
      self:autolinkBook(book_lookup)
      return true
    end
  end
end

function HardcoverApp:linkBookByHardcover()
  local props = self.view.document:getProps()

  local identifiers = parseIdentifiers(props.identifiers)
  if identifiers.book_slug or identifiers.edition_id then
    local user_id = self:getUserId()
    local book_lookup = Api:findBookByIdentifiers({ book_slug = identifiers.book_slug, edition_id = identifiers.edition_id }, user_id)
    if book_lookup then
      self:autolinkBook(book_lookup)
      return true
    end
  end
end

function HardcoverApp:linkBookByTitle()
  local props = self.view.document:getProps()

  local results = Api:findBooks(props.title, props.authors, self:getUserId())
  if results and #results > 0 then
    self:autolinkBook(results[1])
    return true
  end
end

function HardcoverApp:clearLink()
  self:_updateBookSetting(self.ui.document.file, { _delete = { 'book_id', 'edition_id', 'edition_format', 'pages', 'title' }})
  self:registerHighlight()
end

function HardcoverApp:getUserId()
  local user_id = self.settings:readSetting(SETTING_USER_ID)
  if not user_id then
    local me = Api:me()
    user_id = me.id
    self:_updateSetting(SETTING_USER_ID, user_id)
  end

  return user_id
end


function HardcoverApp:addToMainMenu(menu_items)
  if not self.view then
    return
  end

  menu_items.hardcover = {
    --sorting_hint = "navi",
    --reader = true,
    text_func = function()
      return self:bookLinked() and _("Hardcover: \u{F0C1}") or _("Hardcover") -- F127 -> broken link F0C1 link
    end,
    sub_item_table_func = function() return self:getSubMenuItems() end,
  }
end

function HardcoverApp:findBookOptions(force_search)
  local props = self.view.document:getProps()

  local identifiers = parseIdentifiers(props.identifiers)

  local user_id = self:getUserId()

  if not force_search then
    local book_lookup = Api:findBookByIdentifiers(identifiers, user_id)
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

  return title, Api:findBooks(title, props.authors, user_id)
end

function HardcoverApp:buildDialog(title, items, active_item, book_callback, search_callback, search)
  book_callback = book_callback or self.linkBook

  local callback = function(book)
    self.search_dialog:onClose()

    book_callback(self, book)
    if self.state.menu_instance then
      self.state.menu_instance:updateItems()
      self.state.menu_instance = nil
    end
  end

  if self.search_dialog then
    self.search_dialog:free()
  end

  self.search_dialog = SearchDialog:new {
    compatibility_mode = self:compatibilityMode(),
    title = title,
    items = items,
    active_item = active_item,
    select_book_cb = callback,
    search_callback = search_callback,
    search_value = search
  }
end

function HardcoverApp:cacheUserBook()
  local status, errors = Api:findUserBook(self:getLinkedBookId(), self:getUserId())
  self.state.book_status = status or {}

  return errors
end

function HardcoverApp:cachePageMap()
  if not self.ui.document.getPageMap then
    return
  end
  local page_map = self.ui.document:getPageMap()
  if not page_map then
    return
  end

  local lookup = {}
  local last_label
  local real_page = 1
  local last_page = 1

  for _,v in ipairs(page_map) do
    for i=last_page, v.page, 1 do
      lookup[i] = real_page
    end

    if v.label ~= last_label then
      real_page = real_page + 1
      last_label = v.label
    end
    lookup[v.page] = real_page
    last_page = v.page
  end

  self.state.page_map = lookup
end

function HardcoverApp:newRelease()
  local responseBody = {}
  local res, code, responseHeaders = https.request {
    url = RELEASE_API,
    sink = ltn12.sink.table(responseBody),
  }

  if code == 200 or code == 304 then
    local data = json.decode(table.concat(responseBody), json.decode.simple)
    if data and #data > 0 then
      local tag = data[1].tag_name
      local index = 1
      for str in string.gmatch(tag, "([^.]+)") do
        local part = tonumber(str)

        if part < VERSION[index] then
          return nil
        elseif part > VERSION[index] then
          return tag
        end
        index = index + 1
      end
    end
  end
end

function HardcoverApp:updateSearchResults(search)
  local books = Api:findBooks(search, nil, self:getUserId())
  self.search_dialog:setItems(self.search_dialog.title, books, self.search_dialog.active_item)
  self.search_dialog.search_value = search
  return true, false
end

function HardcoverApp:getSubMenuItems()
  return {
    {
      text_func = function()
        if self:bookLinked() then
          -- need to show link information somehow. Maybe store title
          local title = self:getLinkedTitle()
          if not title then
            title = self:getLinkedBookId()
          end
          return _("Linked book: " .. title)
        else
          return _("Link book")
        end
      end,
      hold_callback = function(menu_instance)
        if self:bookLinked() then
          self:clearLink()
          menu_instance:updateItems()
        end
      end,
      keep_menu_open = true,
      callback = function(menu_instance)
        local force_search = self:bookLinked()
        local search_value, books = self:findBookOptions(force_search)
        self:buildDialog(
          "Select book",
          books,
          { book_id = self:getLinkedBookId() },
          nil,
          function(search) return self:updateSearchResults(search) end,
          search_value
        )

        UIManager:show(self.search_dialog)
        self.state.menu_instance = menu_instance
      end,
    },
    {
      text_func = function()
        local edition_format = self:getLinkedEditionFormat()
        local title = "Change edition"

        if edition_format then
          title = title .. ": " .. edition_format
        elseif self:getLinkedEditionId() then
          return title .. ": physical book"
        end

        return _(title)
      end,
      enabled_func = function()
        return self:bookLinked()
      end,
      callback = function(menu_instance)
        local editions = Api:findEditions(self:getLinkedBookId(), self:getUserId())
        -- need to show "active" here, and prioritize current edition if available
        self:buildDialog("Select edition", editions, { edition_id = self:getLinkedEditionId() })
        UIManager:show(self.search_dialog)
        self.state.menu_instance = menu_instance
      end,
      keep_menu_open = true,
      separator = true
    },
    {
      text = _("Automatically track progress"),
      checked_func = function()
        return self:syncEnabled()
      end,
      enabled_func = function()
        return self:bookLinked()
      end,
      callback = function()
        local sync = not self:syncEnabled()
        self:setSync(sync)
      end,
    },
    {
      text = _("Update status"),
      enabled_func = function()
        return self:bookLinked()
      end,
      sub_item_table_func = function()
        self:cacheUserBook()
        return self:getStatusSubMenuItems()
      end,
      separator = true
    },
    {
      text = _("Settings"),
      sub_item_table_func = function() return self:getSettingsSubMenuItems() end,
    },
    {
      text = _("About"),
      callback = function()
        local new_release = self:newRelease()
        local version = table.concat(VERSION, ".")
        local new_release_str = ""
        if new_release then
          new_release_str = " (latest v" .. new_release .. ")"
        end
        local settings_file = DataStorage:getSettingsDir() .. "/" .. "hardcoversync_settings.lua"

        UIManager:show(InfoMessage:new{
          text = [[
Hardcover plugin
v]] .. version .. new_release_str .. [[


Updates book progress and status on Hardcover.app

Project:
github.com/billiam/hardcoverapp.koplugin

Settings:
]] .. settings_file,
          face = Font:getFace("cfont", 18),
          show_icon = false,
        })
      end,
      keep_menu_open = true
    }
  }
end

function HardcoverApp:updateCurrentBookStatus(status, privacy_setting_id)
  self:updateBookStatus(self.ui.document.file, status, privacy_setting_id)
  if not self.state.book_status.id then
    showError("Book status could not be updated")
  end
end

function HardcoverApp:updateBookStatus(filename, status, privacy_setting_id)
  local settings = self:_readBookSettings(filename)
  local book_id = settings.book_id
  local edition_id = settings.edition_id

  self.state.book_status = Api:updateUserBook(book_id, status, privacy_setting_id, edition_id) or {}
end

function HardcoverApp:changeBookVisibility(visibility)
  self:cacheUserBook()
  if self.state.book_status.id then
    self:updateCurrentBookStatus(self.state.book_status.status_id, visibility)
  end
end

function HardcoverApp:getVisibilitySubMenuItems()
  return {
    {
      text = _(privacy_labels[PRIVACY_PUBLIC]),
      checked_func = function()
        return self.state.book_status.privacy_setting_id == PRIVACY_PUBLIC
      end,
      callback = function()
        self:changeBookVisibility(PRIVACY_PUBLIC)
      end,
      radio = true,
    },
    {
      text = _(privacy_labels[PRIVACY_FOLLOWS]),
      checked_func = function()
        return self.state.book_status.privacy_setting_id == PRIVACY_FOLLOWS
      end,
      callback = function()
        self:changeBookVisibility(PRIVACY_FOLLOWS)
      end,
      radio = true
    },
    {
      text = _(privacy_labels[PRIVACY_PRIVATE]),
      checked_func = function()
        return self.state.book_status.privacy_setting_id == PRIVACY_PRIVATE
      end,
      callback = function()
        self:changeBookVisibility(PRIVACY_PRIVATE)
      end,
      radio = true
    },
  }
end

function HardcoverApp:getStatusSubMenuItems()
  return {
    {
      text = _(ICON_BOOKMARK .. " Want To Read"),
      checked_func = function()
        return self.state.book_status.status_id == STATUS_TO_READ
      end,
      callback = function()
        self:updateCurrentBookStatus(STATUS_TO_READ)
      end,
      radio = true
    },
    {
      text = _(ICON_OPEN_BOOK .. " Currently Reading"),
      checked_func = function()
        return self.state.book_status.status_id == STATUS_READING
      end,
      callback = function()
        self:updateCurrentBookStatus(STATUS_READING)
      end,
      radio = true
    },
    {
      text = _(ICON_CHECKMARK .. " Read"),
      checked_func = function()
        return self.state.book_status.status_id == STATUS_FINISHED
      end,
      callback = function()
        self:updateCurrentBookStatus(STATUS_FINISHED)
      end,
      radio = true
    },
    {
      text = _(ICON_STOP_CIRCLE .. " Did Not Finish"),
      checked_func = function()
        return self.state.book_status.status_id == STATUS_DNF
      end,
      callback = function()
        self:updateCurrentBookStatus(STATUS_DNF)
      end,
      radio = true,
    },
    {
      text = _(ICON_TRASH .. " Remove"),
      enabled_func = function()
        return self.state.book_status.status_id ~= nil
      end,
      callback = function(menu_instance)
        local result = Api:removeRead(self.state.book_status.id)
        if result and result.id then
          self.state.book_status = {}
          menu_instance:updateItems()
        end
      end,
      keep_menu_open = true,
      separator = true
    },
    {
      text_func = function()
        local reads = self.state.book_status.user_book_reads
        local current_page = reads and reads[#reads] and reads[#reads].progress_pages or 0
        local max_pages = self:pages()

        if not max_pages then
          max_pages = "???"
        end

        return T(_("Update page: %1 of %2"), current_page, max_pages)
      end,
      enabled_func = function()
        return self.state.book_status.status_id == STATUS_READING and self:pages()
      end,
      callback = function(menu_instance)
        local reads = self.state.book_status.user_book_reads
        local current_read = reads and reads[#reads]
        local current_page = current_read and current_read.progress_pages or 0
        local max_pages = self:pages()

        local spinner = SpinWidget:new{
          value = current_page,
          value_min = 0,
          value_max = max_pages,
          value_step = 1,
          value_hold_step = 20,
          ok_text = _("Set page"),
          title_text = _("Set current page"),
          callback = function(spin)
            local page = spin.value
            local result

            if current_read then
              result = Api:updatePage(current_read.id, current_read.edition_id, page, current_read.started_at)
            else
              local start_date = os.date("%Y-%m-%d")
              result = Api:createRead(self.state.book_status.id, self.state.book_status.edition_id, page, start_date)
            end

            if result then
              self.state.book_status = result
              menu_instance:updateItems()
            else

            end
          end
        }
        UIManager:show(spinner)
      end,
      keep_menu_open = true
    },
    {
      text = _("Add a note"),
      enabled_func = function()
        return self.state.book_status.id ~= nil
      end,
      callback = function()
        local reads = self.state.book_status.user_book_reads
        local current_read = reads and reads[#reads]
        local current_page = current_read and current_read.progress_pages or 0

        -- allow premapped page
        self:journalEntryForm("", current_page, self.ui.document:getPageCount(), self:pages(), current_page,"note")
      end,
      keep_menu_open = true
    },
    {
      text_func = function()
        local text
        if self.state.book_status.rating then
          text = "Update rating"
          local whole_star = math.floor(self.state.book_status.rating)
          local star_string = string.rep(ICON_STAR, whole_star)
          if self.state.book_status.rating - whole_star > 0 then
            star_string = star_string .. ICON_HALF_STAR
          end
          text = text .. ": " .. star_string
        else
          text = "Set rating"
        end

        return _(text)
      end,
      enabled_func = function()
        return self.state.book_status.id ~= nil
      end,
      callback = function(menu_instance)
        local rating = self.state.book_status.rating

        local spinner = SpinWidget:new{
          ok_always_enabled = rating == nil,
          value = rating or 2.5,
          value_min = 0,
          value_max = 5,
          value_step = 0.5,
          value_hold_step = 2,
          precision = "%.1f",
          ok_text = _("Save"),
          title_text = _("Set Rating"),
          callback = function(spin)
            local result = Api:updateRating(self.state.book_status.id, spin.value)
            if result then
              self.state.book_status = result
              menu_instance:updateItems()
            else
              showError("Rating could not be saved")
            end
          end
        }
        UIManager:show(spinner)
      end,
      hold_callback = function(menu_instance)
        local result = Api:updateRating(self.state.book_status.id, 0)
        if result then
          self.state.book_status = result
          menu_instance:updateItems()
        end
      end,
      keep_menu_open = true,
      separator = true
    },
    {
      text = _("Set status visibility"),
      enabled_func = function()
        return self.state.book_status.id ~= nil
      end,
      sub_item_table_func = function()
        return self:getVisibilitySubMenuItems()
      end,
    },
  }
end

function HardcoverApp:tryAutolink()
  if self:bookLinked() then
    return
  end

  local linked = false
  if self.settings:readSetting(SETTING_LINK_BY_ISBN) then
    linked = self:linkBookByIsbn()
  end

  if not linked and self.settings:readSetting(SETTING_LINK_BY_HARDCOVER) then
    linked = self:linkBookByHardcover()
  end

  if not linked and self.settings:readSetting(SETTING_LINK_BY_TITLE) then
    linked = self:linkBookByTitle()
  end
end

function HardcoverApp:getSettingsSubMenuItems()
  return {
    {
      text = "Automatically link by ISBN",
      checked_func = function()
        return self.settings:readSetting(SETTING_LINK_BY_ISBN) == true
      end,
      callback = function()
        local setting = self.settings:readSetting(SETTING_LINK_BY_ISBN) == true
        self:_updateSetting(SETTING_LINK_BY_ISBN, not setting)

        if not setting then
          self:tryAutolink()
        end
      end
    },
    {
      text = "Automatically link by Hardcover identifiers",
      checked_func = function()
        return self.settings:readSetting(SETTING_LINK_BY_HARDCOVER) == true
      end,
      callback = function()
        local setting = self.settings:readSetting(SETTING_LINK_BY_HARDCOVER) == true
        self:_updateSetting(SETTING_LINK_BY_HARDCOVER, not setting)

        if not setting then
          self:tryAutolink()
        end
      end
    },
    {
      text = "Automatically link by title and author",
      checked_func = function()
        return self.settings:readSetting(SETTING_LINK_BY_TITLE) == true
      end,
      callback = function()
        local setting = self.settings:readSetting(SETTING_LINK_BY_TITLE) == true
        self:_updateSetting(SETTING_LINK_BY_TITLE, not setting)

        if not setting then
          self:tryAutolink()
        end
      end,
      separator = true
    },
    {
      text_func = function()
        return "Track progress frequency: " .. self:trackFrequency() .. "min"
      end,
      callback = function(menu_instance)
        local spinner = SpinWidget:new{
          value = self:trackFrequency(),
          value_min = 1,
          value_max = 120,
          value_step = 1,
          value_hold_step = 6,
          ok_text = _("Save"),
          title_text = _("Set track progress"),
          callback = function(spin)
            self:changeTrackFrequency(spin.value)
            menu_instance:updateItems()
          end
        }

        UIManager:show(spinner)
      end,
      keep_menu_open = true
    },
    {
      text = "Always track progress by default",
      checked_func = function()
        return self.settings:readSetting(SETTING_ALWAYS_SYNC) == true
      end,
      callback = function()
        local setting = self.settings:readSetting(SETTING_ALWAYS_SYNC) == true
        self:_updateSetting(SETTING_ALWAYS_SYNC, not setting)
      end,
    },
    {
      text = "Compatibility mode",
      checked_func = function()
        return self:compatibilityMode()
      end,
      callback = function()
        local setting = self:compatibilityMode()
        self:_updateSetting(SETTING_COMPATIBILITY_MODE, not setting)
      end,
      hold_callback = function()
        UIManager:show(InfoMessage:new{
          text = [[Disable fancy menu for book and edition search results.

May improve compatibility for some versions of KOReader]],
        })
      end
    }
  }
end

return HardcoverApp
