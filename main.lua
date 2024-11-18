--[[--
@module koplugin.HardcoverApp
--]]--

--TODO: trap request loading
local Api = require("hardcover_api")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")  -- luacheck:ignore
local LuaSettings = require("frontend/luasettings")
local SearchDialog = require("search_dialog")
local SpinWidget = require("ui/widget/spinwidget")
local T = require("ffi/util").template
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local logger = require("logger")
local os = require("os")
local math = require("math")
local throttle = require("throttle")

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

local function parseIdentifiers(identifiers)
  result = {}

  if not identifiers then
    return result
  end

  -- TODO: are multiple identifiers comma/semicolon delimited?
  for line in identifiers:gmatch("%s*([^%s]+)%s*") do
    -- check for hardcover: and hardcover-edition:
    local hc = string.match(line, "hardcover:([%w_-]+)")
    if hc then
      identifiers.book_slug = hc
    end

    local hc_edition = string.match(line, "hardcover-edition:(%d+)")

    if hc_edition then
      identifiers.edition_id = hc_edition
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

function HardcoverApp:onDispatcherRegisterActions()
  Dispatcher:registerAction("hardcover_link", { category = "none", event = "HardcoverLink", title = _("Hardcover Link"), general = true, })
end

function HardcoverApp:init()
  self.state = {
    page = nil,
    pos = nil,
    search_results = {},
    book_status = {}
  }
  self.settings = LuaSettings:open(("%s/%s"):format(DataStorage:getSettingsDir(), "hardcoversync_settings.lua"))

  self:onDispatcherRegisterActions()

  self.ui.menu:registerToMainMenu(self)
end

function HardcoverApp:_handlePageUpdate(filename, page, document_pages, mapped_page, immediate)
  local book_settings = self:_readBookSettings(filename)
  if not book_settings.book_id or not book_settings.sync then
    return
  end

  if self.state.book_status.status_id ~= STATUS_READING then
    return
  end

  if not mapped_page then
    mapped_page = math.floor(( page / document_pages) * book_settings.pages)
  end

  local reads = self.state.book_status.user_book_reads
  local current_read = reads and reads[#reads]
  if not current_read then
    return
  end

  local apiUpdate = function()
    Api:updatePage(current_read.id, current_read.edition_id, mapped_page, current_read.started_at)
  end

  if immediate then
    apiUpdate()
  else
    UIManager:scheduleIn(1, apiUpdate)
  end
end

HardcoverApp._throttledHandlePageUpdate, HardcoverApp._cancelPageUpdate = throttle(30, HardcoverApp._handlePageUpdate)

function HardcoverApp:pageUpdateEvent(page)
  self.state.page = page
  local document_pages = self.ui.document:getPageCount() -- non-translated
  local mapped_page = self.state.page_map and self.state.page_map[page]
  if self.state.book_status.id then
    self:_throttledHandlePageUpdate(self.view.document.file, page, document_pages, mapped_page)
  end
end

HardcoverApp.onPageUpdate = HardcoverApp.pageUpdateEvent
function HardcoverApp:onPosUpdate(_, page)
  self:pageUpdateEvent(page)
end

function HardcoverApp:onUpdatePos()
  self:cachePageMap()
end

function HardcoverApp:onReaderReady()
  self:cachePageMap()

  local book_settings = self:_readBookSettings(self.view.document.file)
  if book_settings.book_id and book_settings.sync then
    self:cacheUserBook()
  end
end

function HardcoverApp:onDocumentClose()
  self.state.book_status = {}
  self.state.page_map = nil
end

function HardcoverApp:onSuspend()
  self:_cancelPageUpdate()
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
    local privacy_setting_id = user_book.privacy_setting_id or user_book.pending_visibility or self:defaultVisibility()

    self:updateBookStatus(file, status, privacy_setting_id)
  end
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
  local setting = {}
  if value then
    setting.sync = true
  else
    setting._delete = { "sync" }
  end
  self:_updateBookSetting(self.view.document.file, setting)
end

function HardcoverApp:editionLinked()
  return self:_readBookSetting(self.view.document.file, "edition_id") ~= nil
end

function HardcoverApp:readLinked()
  return self:_readBookSetting(self.view.document.file, "read_id") ~= nil
end

-- TODO: Cache until book closed/opened/linked/unlinked
function HardcoverApp:bookLinked()
  return self:getLinkedBookId() ~= nil
end

function HardcoverApp:getLinkedTitle()
  return self:_readBookSetting(self.view.document.file, "title")
end

function HardcoverApp:getLinkedBookId()
  return self:_readBookSetting(self.view.document.file, "book_id")
end

function HardcoverApp:getLinkedEditionFormat()
  return self:_readBookSetting(self.view.document.file, "edition_format")
end

function HardcoverApp:getLinkedEditionId()
  return self:_readBookSetting(self.view.document.file, "edition_id")
end

function HardcoverApp:syncEnabled()
  return self:_readBookSetting(self.view.document.file, "sync") == true
end

function HardcoverApp:pendingBookVisibility()
  return self:_readBookSetting(self.view.document.file, "visibility")
end

function HardcoverApp:pages()
  return self:_readBookSetting(self.view.document.file, "pages")
end

function HardcoverApp:clearCurrentPendingBookVisibility()
  return self:clearPendingBookVisibility(self.view.document.file)
end

function HardcoverApp:clearPendingBookVisibility(filename)
  return self:_updateBookSetting(filename, { _delete = { "visibility" }})
end

function HardcoverApp:setPendingBookVisibility(visibility)
  return self:_updateBookSetting(self.view.document.file, { visibility = visibility })
end

function HardcoverApp:defaultVisibility()
  return self.settings:readSetting("default_visibility")
end

function HardcoverApp:linkBook(book)
  local filename = self.view.document.file

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

  self:_updateBookSetting(filename, new_settings)

  self:cacheUserBook()
  if book.book_id and self.state.book_status.id then
    if new_settings.edition_id and new_settings.edition_id ~= self.state.book_status.edition_id then
      self.state.book_status = Api:updateUserBook(new_settings.book_id, self.state.book_status.status_id, self.state.book_status.privacy_setting_id, new_settings.edition_id) or {}
    end
  end
end

function HardcoverApp:clearLink()
  self:_updateBookSetting(self.view.document.file, { _delete = { 'book_id', 'title', 'edition_id' }})
end

function HardcoverApp:getUserId()
  local user_id = self.settings:readSetting("user_id")
  if not user_id then
    local me = Api:me()
    user_id = me.id
    self:_updateSetting("user_id", user_id)
  end

  return user_id
end


function HardcoverApp:addToMainMenu(menu_items)
  if not self.view then
    return
  end
  local this = self

  menu_items.hardcover = {
    --sorting_hint = "navi",
    --reader = true,
    text_func = function()
      return self:bookLinked() and _("Hardcover: \u{F0C1}") or _("Hardcover") -- F127 -> broken link F0C1 link
    end,
    sub_item_table_func = function() return self:getSubMenuItems() end,
  }
end

function HardcoverApp:bookSearchList()

end

function HardcoverApp:findBookOptions(force_search)
  local props = self.view.document:getProps()

  local identifiers = parseIdentifiers(props.identifiers)

  local user_id = self:getUserId()

  if not force_search then
    local book_lookup = Api:findBookByIdentifiers(identifiers, user_id)
    if book_lookup then
      return { book_lookup }
    end
  end
  -- TODO: When search api is ready, parse title from filename if no title available

  return Api:findBooks(props.title, props.authors, user_id)
end

function HardcoverApp:buildDialog(title, items, active_item)
  if self.search_dialog then
    self.search_dialog:setItems(title, items, active_item)
  else
    self.search_dialog = SearchDialog:new {
      title = title,
      items = items,
      active_item = active_item,
      select_book_cb = function(book)
        self.search_dialog:onClose()

        self:linkBook(book)
        if self.state.menu_instance then
          self.state.menu_instance:updateItems()
          self.state.menu_instance = nil
        end
      end
    }
  end
end

function HardcoverApp:cacheUserBook()
  self.state.book_status = Api:findUserBook(self:getLinkedBookId(), self:getUserId()) or {}
end

function HardcoverApp:cachePageMap()
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
        local books = self:findBookOptions(force_search)
        self:buildDialog("Select book", books, { book_id = self:getLinkedBookId() })
        UIManager:show(self.search_dialog)
        self.state.menu_instance = menu_instance
      end,
    },
    {
      -- TODO: show edition format
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
      text = _("Track progress"),
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
    },
    {
      text = _("Set status visibility"),
      enabled_func = function()
        return self:bookLinked()
      end,
      sub_item_table_func = function()
        self:cacheUserBook()
        return self:getVisibilitySubMenuItems()
      end,
      separator = true
    },
    {
      text = _("Settings"),
      sub_item_table_func = function() return self:getSettingsSubMenuItems() end,
    },
  }
end

function HardcoverApp:effectiveVisibilitySetting()
  if self.state.book_status.privacy_setting_id ~= nil then
    return self.state.book_status.privacy_setting_id
  end

  local pending_visibility = self:pendingBookVisibility()
  if pending_visibility ~= nil then
    return pending_visibility
  end

  return self:defaultVisibility()
end

function HardcoverApp:updateCurrentBookStatus(status, privacy_setting_id)
  privacy_setting_id = privacy_setting_id or self:effectiveVisibilitySetting()
  self:updateBookStatus(self.view.document.file, status, privacy_setting_id)
end

function HardcoverApp:updateBookStatus(filename, status, privacy_setting_id)
  local settings = self:_readBookSettings(filename)
  local book_id = settings.book_id
  local edition_id = settings.edition_id
  self.state.book_status = Api:updateUserBook(book_id, status, privacy_setting_id, edition_id) or {}
  self:clearPendingBookVisibility(filename)
end

function HardcoverApp:changeBookVisibility(visibility)
  self:cacheUserBook()
  if self.state.book_status.id then
    self:updateCurrentBookStatus(self.state.book_status.status_id, visibility)
  else
    self:setPendingBookVisibility(visibility)
  end
end

function HardcoverApp:getVisibilitySubMenuItems()
  return {
    {
      text = _("Public"),
      checked_func = function()
        local visibility = self:effectiveVisibilitySetting()
        return visibility == PRIVACY_PUBLIC or visibility == nil
      end,
      callback = function()
        self:changeBookVisibility(PRIVACY_PUBLIC)
      end,
      radio = true,

    },
    {
      text = _("Follows"),
      checked_func = function()
        return self:effectiveVisibilitySetting() == PRIVACY_FOLLOWS
      end,
      callback = function()
        self:changeBookVisibility(PRIVACY_FOLLOWS)
      end,
      radio = true
    },
    {
      text = _("Private"),
      checked_func = function()
        return self:effectiveVisibilitySetting() == PRIVACY_PRIVATE
      end,
      callback = function()
        self:changeBookVisibility(PRIVACY_PRIVATE)
      end,
      radio = true
    },
  }
end

function HardcoverApp:getDefaultVisibilitySubMenuItems()
  return {
    {
      text = _("Public"),
      checked_func = function()
        local visibility = self:defaultVisibility()
        return visibility == PRIVACY_PUBLIC or visibility == nil
      end,
      callback = function()
        self:_updateSetting("default_visibility", PRIVACY_PUBLIC)
      end,
      radio = true,

    },
    {
      text = _("Follows"),
      checked_func = function()
        return self:defaultVisibility() == PRIVACY_FOLLOWS
      end,
      callback = function()
        self:_updateSetting("default_visibility", PRIVACY_FOLLOWS)
      end,
      radio = true
    },
    {
      text = _("Private"),
      checked_func = function()
        return self:defaultVisibility() == PRIVACY_PRIVATE
      end,
      callback = function()
        self:_updateSetting("default_visibility", PRIVACY_PRIVATE)
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
        if result then
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
        local current_page = reads and reads[#reads].progress_pages or 0
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
            end
          end
        }
        UIManager:show(spinner)
      end,
      keep_menu_open = true
    },
  }
end

function HardcoverApp:getSettingsSubMenuItems()
  return {
    {
      text = "Automatically link by ISBN",
      checked_func = function()
        return false
      end,
    },
    {
      text = "Automatically link by Hardcover identifiers",
      checked_func = function()
        return false
      end,
    },
    {
      text = "Automatically link by title and author",
      checked_func = function()
        return false
      end,
    },
    {
      text = "Update frequency",
      -- every (x) minutes
      -- before exit/sleep? (when done reading)
        -- when book closed, maybe opened
    },
    {
      text = "Always track progress by default",
      checked_func = function()
        return false
      end,
    },
    {
      text = _("Default status visibility"),
      sub_item_table_func = function()
        return self:getDefaultVisibilitySubMenuItems()
      end
    },
  }
end

return HardcoverApp
