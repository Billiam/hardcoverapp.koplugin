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

local _t = require("hardcover/lib/table_util")
local Api = require("hardcover/lib/hardcover_api")
local AutoWifi = require("hardcover/lib/auto_wifi")
local Cache = require("hardcover/lib/cache")
local debounce = require("hardcover/lib/debounce")
local Hardcover = require("hardcover/lib/hardcover")
local HardcoverSettings = require("hardcover/lib/hardcover_settings")
local PageMapper = require("hardcover/lib/page_mapper")
local Scheduler = require("hardcover/lib/scheduler")
local throttle = require("hardcover/lib/throttle")
local User = require("hardcover/lib/user")

local DialogManager = require("hardcover/lib/ui/dialog_manager")
local HardcoverMenu = require("hardcover/lib/ui/hardcover_menu")

local HARDCOVER = require("hardcover/lib/constants/hardcover")
local SETTING = require("hardcover/lib/constants/settings")

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
    title = _("Hardcover: Link book"),
    general = true,
  })

  Dispatcher:registerAction("hardcover_track", {
    category = "none",
    event = "HardcoverTrack",
    title = _("Hardcover: Track progress"),
    general = true,
  })

  Dispatcher:registerAction("hardcover_stop_track", {
    category = "none",
    event = "HardcoverStopTrack",
    title = _("Hardcover: Stop tracking progress"),
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
  self.wifi = AutoWifi:new {
    settings = self.settings
  }
  self.hardcover = Hardcover:new {
    cache = self.cache,
    dialog_manager = self.dialog_manager,
    settings = self.settings,
    state = self.state,
    ui = self.ui,
    wifi = self.wifi
  }

  self.menu = HardcoverMenu:new {
    enabled = true,

    cache = self.cache,
    dialog_manager = self.dialog_manager,
    hardcover = self.hardcover,
    page_mapper = self.page_mapper,
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

function HardcoverApp:onHardcoverLink()
  self.hardcover:showLinkBookDialog(false, function(book)
    UIManager:show(Notification:new {
      text = _("Linked to: " .. book.title),
    })
  end)
end

function HardcoverApp:onHardcoverTrack()
  self.settings:setSync(true)
  UIManager:nextTick(function()
    UIManager:show(Notification:new {
      text = _("Progress tracking enabled")
    })
  end)
end

function HardcoverApp:onHardcoverStopTrack()
  self.settings:setSync(false)
  UIManager:show(Notification:new {
    text = _("Progress tracking disabled")
  })
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
    self.wifi:withWifi(function()
      local result = Api:updatePage(current_read.id, current_read.edition_id, mapped_page, current_read.started_at)
      if result then
        self.state.book_status = result
      end
    end)
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
  local remote_pages = self.settings:pages()

  if self.settings:trackByTime() then
    local mapped_page = self.page_mapper:getMappedPage(page, document_pages, remote_pages)

    self:_throttledHandlePageUpdate(self.ui.document.file, mapped_page)
    self.page_update_pending = true
  elseif self.settings:trackByProgress() and self.state.last_page then
    local percent_interval = self.settings:trackPercentageInterval()

    local previous_percent = self.page_mapper:getRemotePagePercent(
      self.state.last_page,
      document_pages,
      remote_pages
    )

    local current_percent, mapped_page = self.page_mapper:getRemotePagePercent(
      self.state.page,
      document_pages,
      remote_pages
    )

    local last_compare = math.floor(previous_percent * 100 / percent_interval)
    local current_compare = math.floor(current_percent * 100 / percent_interval)

    if last_compare ~= current_compare then
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
  self.state.read_cache_started = false

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

function HardcoverApp:onSuspend()
  self:cancelPendingUpdates()

  Scheduler:clear()
  self.state.read_cache_started = false
end

function HardcoverApp:onResume()
  if self.settings:readSetting(SETTING.ENABLE_WIFI) and self.ui.document and self.settings:syncEnabled() then
    UIManager:scheduleIn(2, self.startReadCache, self)
  end
end

function HardcoverApp:onNetworkDisconnecting()
  --logger.warn("HARDCOVER on disconnecting")
  if self.settings:readSetting(SETTING.ENABLE_WIFI) then
    return
  end

  self:cancelPendingUpdates()

  Scheduler:clear()
  self.state.read_cache_started = false

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
  if self.ui.document and self.settings:syncEnabled() and not self.state.read_cache_started then
    --logger.warn("HARDCOVER on connected", self.state.read_cache_started)

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
        self.wifi:withWifi(function()
          marker()
        end)
      end
    end)
  else
    self.wifi:withWifi(function()
      marker()
      UIManager:show(InfoMessage:new {
        text = _("Hardcover status saved"),
        timeout = 2
      })
    end)
  end
end

function HardcoverApp:syncFileUpdates(filename)
  return self.settings:readBookSetting(filename, "book_id") and self.settings:fileSyncEnabled(filename)
end

function HardcoverApp:onDocSettingsItemsChanged(file, doc_settings)
  if not self:syncFileUpdates(file) or not doc_settings then
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
    self.wifi:withWifi(function()
      self.cache:updateBookStatus(file, status, user_book.privacy_setting_id)

      UIManager:show(InfoMessage:new {
        text = _("Hardcover status saved"),
        timeout = 2
      })
    end)
  end
end

function HardcoverApp:startReadCache()
  --logger.warn("HARDCOVER start read cache")
  if self.state.read_cache_started then
    --logger.warn("HARDCOVER Cache already started")
    return
  end

  if not self.ui.document then
    --logger.warn("HARDCOVER read cache fired outside of document")
    return
  end

  self.state.read_cache_started = true

  local cancel

  local restart = function(delay)
    --logger.warn("HARDCOVER restart cache fetch")
    delay = delay or 60
    cancel()
    self.state.read_cache_started = false
    UIManager:scheduleIn(delay, self.startReadCache, self)
  end

  cancel = Scheduler:withRetries(6, 3, function(success, fail)
      Trapper:wrap(function()
        local book_settings = self.settings:readBookSettings(self.ui.document.file) or {}
        --logger.warn("HARDCOVER", book_settings)
        if book_settings.book_id then
          if self.state.book_status.id then
            return success()
          else
            self.wifi:withWifi(function()
              if not NetworkManager:isConnected() then
                return restart()
              end

              local err = self.cache:cacheUserBook()
              --if err then
              --logger.warn("HARDCOVER cache error", err)
              --end
              if err and err.completed == false then
                return fail(err)
              end

              success()
            end)
          end
        else
          self.hardcover:tryAutolink()
          if self.settings:bookLinked() and self.settings:syncEnabled() then
            return restart(2)
          end
        end
      end)
    end,

    function()
      if self.settings:syncEnabled() then
        --logger.warn("HARDCOVER enabling page turns")

        self.state.process_page_turns = true
      end
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
