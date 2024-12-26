local _ = require("gettext")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local DocSettings = require("docsettings")
local logger = require("logger")
local math = require("math")

local NetworkManager = require("ui/network/manager")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")

local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")

local WidgetContainer = require("ui/widget/container/widgetcontainer")

local _t = require("lib/table_util")
local Api = require("lib/hardcover_api")
local Cache = require("lib/cache")
local debounce = require("lib/debounce")
local Hardcover = require("lib/hardcover")
local HardcoverSettings = require("lib/hardcover_settings")
local PageMapper = require("lib/page_mapper")
local Scheduler = require("lib/scheduler")
local throttle = require("lib/throttle")
local User = require("lib/user")

local DialogManager = require("lib/ui/dialog_manager")
local HardcoverMenu = require("lib/ui/hardcover_menu")

local HARDCOVER = require("lib/constants/hardcover")
local SETTING = require("lib/constants/settings")

local HardcoverApp = WidgetContainer:extend {
  name = "hardcoverappsync",
  is_doc_only = false,
  state = nil,
  settings = nil,
  width = nil,
  enabled = true
}

local HIGHLIGHT_MENU_NAME = "13_0_make_hardcover_highlight_item"

function HardcoverApp:onDispatcherRegisterActions()
  Dispatcher:registerAction("hardcover_link", {
    category = "none",
    event = "HardcoverLink",
    title = _("Hardcover Link"),
    general = true,
  })
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
  self.settings = HardcoverSettings:new(
    ("%s/%s"):format(DataStorage:getSettingsDir(), "hardcoversync_settings.lua"),
    self.ui
  )
  self.settings:subscribe(function(field, change, original_value) self:onSettingsChanged(field, change, original_value) end)

  User.settings = self.settings
  Api.on_error = function(err)
    if not err or not self.enabled then
      return
    end

    if _t.dig(err, "extensions", "code") == HARDCOVER.ERROR.JWT or (err.message and string.find(err.message, "JWT")) then
      self:disable()
      UIManager:show(InfoMessage:new {
        text = "Your Hardcover API key is not valid or has expired. Please update it and restart",
        icon = "notice-warning",
      })
    end
  end

  self.cache = Cache:new {
    settings = self.settings,
    state = self.state
  }
  self.hardcover = Hardcover:new {
    cache = self.cache,
    dialog_manager = self.dialog_manager,
    settings = self.settings,
    state = self.state,
    ui = self.ui,
  }
  self.page_mapper = PageMapper:new {
    state = self.state,
    ui = self.ui,
  }
  self.dialog_manager = DialogManager:new {
    page_mapper = self.page_mapper,
    settings = self.settings,
    state = self.state,
    ui = self.ui,
  }
  self.menu = HardcoverMenu:new {
    enabled = true,

    cache = self.cache,
    dialog_manager = self.dialog_manager,
    hardcover = self.hardcover,
    settings = self.settings,
    state = self.state,
    ui = self.ui,
  }

  self:onDispatcherRegisterActions()
  self:initializePageUpdate()
  self.ui.menu:registerToMainMenu(self)
end

function HardcoverApp:_bookSettingChanged(setting, key)
  return setting[key] ~= nil or _t.contains(_t.dig(setting, "_delete"), key)
end

function HardcoverApp:disable()
  self.enabled = false
  if self.menu then
    self.menu.enabled = false
  end
  self:registerHighlight()
end

function HardcoverApp:onSettingsChanged(field, change, original_value)
  if field == SETTING.BOOKS then
    local book_settings = change.config
    if self:_bookSettingChanged(book_settings, "sync") then
      if book_settings.sync then
        if not self.state.book_status.id then
          self:startReadCache()
        end
      else
        self:cancelPendingUpdates()
      end
    end

    if self:_bookSettingChanged(book_settings, "book_id") then
      self:registerHighlight()
    end
  elseif field == SETTING.TRACK_METHOD then
    self:cancelPendingUpdates()
    self:initializePageUpdate()
  elseif field == SETTING.LINK_BY_HARDCOVER or field == SETTING.LINK_BY_ISBN or field == SETTING.LINK_BY_TITLE then
    if change then
      self.hardcover:tryAutolink()
    end
  end
end

function HardcoverApp:_handlePageUpdate(filename, mapped_page, immediate)
  --logger.warn("HARDCOVER: Throttled page update", mapped_page)
  self.page_update_pending = false

  if not self:syncFileUpdates(filename) then
    return
  end

  if self.state.book_status.status_id ~= HARDCOVER.STATUS.READING then
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
  local track_frequency = math.max(math.min(self.settings:trackFrequency(), 120), 1) * 60

  HardcoverApp._throttledHandlePageUpdate, HardcoverApp._cancelPageUpdate = throttle(
    track_frequency,
    HardcoverApp._handlePageUpdate
  )

  HardcoverApp.onPageUpdate, HardcoverApp._cancelPageUpdateEvent = debounce(2, HardcoverApp.pageUpdateEvent)
end

function HardcoverApp:pageUpdateEvent(page)
  self.state.last_page = self.state.page
  self.state.page = page

  if not (self.state.book_status.id and self.settings:syncEnabled()) then
    return
  end
  --logger.warn("HARDCOVER page update event pending")
  local document_pages = self.ui.document:getPageCount()
  local mapped_page = self.page_mapper:getMappedPage(page, document_pages, self.settings:pages())

  if self.settings:trackByTime() then
    self:_throttledHandlePageUpdate(self.ui.document.file, mapped_page)
    self.page_update_pending = true
  elseif self.settings:trackByProgress() and self.state.last_page then
    local percent_interval = self.settings:trackPercentageInterval()

    local original_percent = math.floor(
      self.page_mapper:getMappedPagePercent(self.state.last_page, document_pages, self.settings:pages()) *
      100 / percent_interval
    )

    local new_percent = math.floor(
      self.page_mapper:getMappedPagePercent(self.state.page, document_pages, self.settings:pages()) *
      100 / percent_interval
    )

    if original_percent ~= new_percent then
      self:_handlePageUpdate(self.ui.document.file, mapped_page)
    end
  end
end

function HardcoverApp:onPosUpdate(_, page)
  if self.state.process_page_turns then
    self:pageUpdateEvent(page)
  end
end

function HardcoverApp:onUpdatePos()
  self.page_mapper:cachePageMap()
end

function HardcoverApp:onReaderReady()
  --logger.warn("HARDCOVER on ready")

  self.page_mapper:cachePageMap()
  self:registerHighlight()
  self.state.page = self.ui:getCurrentPage()

  if self.ui.document and (self.settings:syncEnabled() or (not self.settings:bookLinked() and self.settings:autolinkEnabled())) then
    UIManager:scheduleIn(2, self.startReadCache, self)
  end
end

function HardcoverApp:cancelPendingUpdates()
  if self._cancelPageUpdate then
    self:_cancelPageUpdate()
  end

  if self._cancelPageUpdateEvent then
    self:_cancelPageUpdateEvent()
  end

  self.page_update_pending = false
end

function HardcoverApp:onDocumentClose()
  UIManager:unschedule(self.startCacheRead)

  self:cancelPendingUpdates()

  if not self.state.book_status.id and not self.settings:syncEnabled() then
    return
  end

  if self.page_update_pending then
    local mapped_page = self.page_mapper:getMappedPage(
      self.state.page,
      self.ui.document:getPageCount(),
      self.settings:pages()
    )
    self:_handlePageUpdate(self.ui.document.file, mapped_page, true)
  end

  self.process_page_turns = false
  self.page_update_pending = false
  self.state.book_status = {}
  self.state.page_map = nil
end

function HardcoverApp:onNetworkDisconnecting()
  --logger.warn("HARDCOVER on disconnecting")
  self:cancelPendingUpdates()

  Scheduler:clear()

  if self.page_update_pending and self.ui.document and self.state.book_status.id and self.settings:syncEnabled() and self.settings:trackByTime() then
    local mapped_page = self.page_mapper:getMappedPage(
      self.state.page,
      self.ui.document:getPageCount(),
      self.settings:pages()
    )
    self:_handlePageUpdate(self.ui.document.file, mapped_page, true)
  end
  self.page_update_pending = false
end

function HardcoverApp:onNetworkConnected()
  --logger.warn("HARDCOVER on connected")
  if self.ui.document and self.settings:syncEnabled() then
    self:startReadCache()
  end
end

function HardcoverApp:onEndOfBook()
  local file_path = self.ui.document.file

  if not self:syncFileUpdates(file_path) then
    return
  end

  local mark_read = false
  if G_reader_settings:isTrue("end_document_auto_mark") then
    mark_read = true
  end

  if not mark_read then
    local action = G_reader_settings:readSetting("end_document_action") or "pop-up"
    mark_read = action == "mark_read"

    if action == "pop-up" then
      mark_read = 'later'
    end
  end

  if not mark_read then
    return
  end

  local user_id = User:getId()

  local marker = function()
    local book_id = self.settings:readBookSetting(file_path, "book_id")
    local user_book = Api:findUserBook(book_id, user_id) or {}
    self.cache:updateBookStatus(file_path, HARDCOVER.STATUS.FINISHED, user_book.privacy_setting_id)
  end

  if mark_read == 'later' then
    UIManager:scheduleIn(30, function()
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

function HardcoverApp:syncFileUpdates(filename)
  return self.settings:readBookSetting(filename, "book_id") and self.settings:fileSyncEnabled(filename)
end

function HardcoverApp:onDocSettingsItemsChanged(file, doc_settings)
  if not self:syncFileUpdates(file) then
    return
  end

  local status
  if doc_settings.summary.status == "complete" then
    status = HARDCOVER.STATUS.FINISHED
  elseif doc_settings.summary.status == "reading" then
    status = HARDCOVER.STATUS.READING
  end

  if status then
    local book_id = self.settings:readBookSetting(file, "book_id")
    local user_book = Api:findUserBook(book_id, User:getId()) or {}
    self.cache:updateBookStatus(file, status, user_book.privacy_setting_id)

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
      if not NetworkManager:isConnected() then
        return restart()
      end

      Trapper:wrap(function()
        local book_settings = self.settings:readBookSettings(self.ui.document.file)
        --logger.warn("HARDCOVER", book_settings)
        if book_settings.book_id and not self.state.book_status.id then
          if self.settings:syncEnabled() then
            local err = self.cache:cacheUserBook()
            --if err then
            --logger.warn("HARDCOVER cache error", err)
            --end
            if err and err.completed == false then
              return fail(err)
            end
          end
        else
          self.hardcover:tryAutolink()
        end
        success()
      end)
    end,

    function()
      --logger.warn("HARDCOVER enabling page turns")
      self.state.process_page_turns = true
    end,

    function()
      if NetworkManager:isConnected() then
        UIManager:show(Notification:new {
          text = _("Failed to fetch book information from Hardcover"),
        })
      end
    end)
end

function HardcoverApp:registerHighlight()
  self.ui.highlight:removeFromHighlightDialog(HIGHLIGHT_MENU_NAME)

  if self.enabled and self.settings:bookLinked() then
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
          self.dialog_manager:journalEntryForm(
            selected_text.text,
            self.ui.document,
            raw_page,
            self.settings:pages(),
            nil,
            "quote"
          )

          this:onClose()
        end,
      }
    end)
  end
end

function HardcoverApp:addToMainMenu(menu_items)
  if not self.view then
    return
  end

  menu_items.hardcover = self.menu:mainMenu()
end

return HardcoverApp
