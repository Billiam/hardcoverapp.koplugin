--[[--
@module koplugin.HardcoverApp
--]]--

local Dispatcher = require("dispatcher")  -- luacheck:ignore
local Device = require("device")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local logger = require("logger")
local LuaSettings = require("frontend/luasettings")
local DataStorage = require("datastorage")
local Api = require("hardcover_api")
local SearchDialog = require("search_dialog")
local Paginator = require("paginator")

local Screen = Device.screen

local HardcoverApp = WidgetContainer:extend {
  name = "hardcoverappsync",
  is_doc_only = false,
  state = nil,
  settings = nil,
  width = nil
}

function HardcoverApp:parseIdentifiers(identifiers)
  result = {}
  if not identifiers then
    return result
  end

  for line in identifiers:gmatch("%s*([^%s]+)%s*") do
    local str = string.gsub(line, "^[^%s]+%s*:%s*", "")

    if str then
      local len = #str
      if len == 13 then
        result.isbn13 = str
      elseif len == 10 then
        result.isbn = str
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
    search_results = {}
  }


  self.settings = LuaSettings:open(("%s/%s"):format(DataStorage:getSettingsDir(), "hardcoversync_settings.lua"))

  self:onDispatcherRegisterActions()

  self.ui.menu:registerToMainMenu(self)

  --self:me()

  --self:buildDialog()

  --UIManager:forceRePaint()
end


function HardcoverApp:buildDialog(pagination)

end

--function HardcoverApp:addToMainMenu(menu_items)
--  menu_items.hardcover = {
--    text = _("Hardcover"),
--    -- in which menu this should be appended
--    sorting_hint = "more_tools",
--    -- a callback when tapping
--    callback = function()
--      UIManager:show(InfoMessage:new {
--        text = _("Hello, plugin world"),
--      })
--    end,
--  }
--end

--function HardcoverApp:onHelloWorld()
--  local popup = InfoMessage:new {
--    text = _("Hello World"),
--  }
--  UIManager:show(popup)
--end

-- TODO: debounce updates
function HardcoverApp:onPageUpdate(page)
  local props = self.view.document:getProps()

  --logger.warn(props.title, props.authors)
  logger.warn(props)

  self.state.page = page
  --selfdebouncedPageUpdate()
end

function HardcoverApp:debouncedPageUpdate()

end

function HardcoverApp:updatePage()
  --local setting = self.settings.readSetting(self.view.document.file)
  --if setting.sync and setting.editionId then
  --
  --end
end

function HardcoverApp:stopSync()
  self:_updateBookSetting(self.view.document.file, "sync", false)
end

function HardcoverApp:startSync()
  self:_updateBookSetting(self.view.document.file,"sync", true)
end

function HardcoverApp:_updateBookSetting(filename, key, value)
  logger.warn("Book: ", filename, key, value)

  local books = self.settings:child("books")
  local setting = books:child(filename)

  setting.saveSetting(key, value)
  books:saveSetting(filename, setting)
  self.settings:saveSetting("books", books)

  self.settings:flush()
end

function HardcoverApp:_updateSetting(key, value)
  logger.warn("Setting: ", key, value)
  self.settings:saveSetting(key, value)
  self.settings:flush()
end

function HardcoverApp:onPosUpdate(pos)
  self.state.pos = pos
end

--function HardcoverApp:me()
--  return Api:me()
--end

function HardcoverApp:linked()
  return self.settings:child("books"):child(self.view.document.file):readSetting("editionId") ~= nil
end

function HardcoverApp:bookLinked()
  return self.settings:child("books"):child(self.view.document.file):readSetting("bookId") ~= nil
end

function HardcoverApp:updateLinked()
  return self.settings:child("books"):child(self.view.document.file):readSetting("readId") ~= nil
end

function HardcoverApp:enabled()
  return self.settings:child("books"):child(self.view.document.file):readSetting("sync")
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
      return self:linked() and _("Hardcover: \u{F0C1}") or _("Hardcover") -- F127 -> broken link F0C1 link
    end,
    --checked_func = function() return self:_enabled() end,
    --  callback = function(menu)
    --    --if settings.sync then
    --
    --    --end
    --  end,
    --
    sub_item_table_func = function() return this:getSubMenuItems() end,
    --callback = function(menu)

      -- otherwise use submenu?
      --if not self:linked() then
        -- open link list
      --end
    --end,
  }

  --callback = function(menu)
  --  local DateTimeWidget = require("ui/widget/datetimewidget")
  --  local autoturn_seconds = G_reader_settings:readSetting("autoturn_timeout_seconds", 30)
  --  local autoturn_minutes = math.floor(autoturn_seconds * (1/60))
  --  autoturn_seconds = autoturn_seconds % 60
  --  local autoturn_spin = DateTimeWidget:new {
  --    title_text = _("Autoturn time"),
  --    info_text = _("Enter time in minutes and seconds."),
  --    min = autoturn_minutes,
  --    min_max = 60 * 24, -- maximum one day
  --    min_default = 0,
  --    sec = autoturn_seconds,
  --    sec_default = 30,
  --    keep_shown_on_apply = true,
  --    ok_text = _("Set timeout"),
  --    cancel_text = _("Disable"),
  --    cancel_callback = function()
  --      self.enabled = false
  --      G_reader_settings:makeFalse("autoturn_enabled")
  --      self:_unschedule()
  --      menu:updateItems()
  --      self.onResume = nil
  --    end,
  --    ok_always_enabled = true,
  --    callback = function(t)
  --      self.autoturn_sec = t.min * 60 + t.sec
  --      G_reader_settings:saveSetting("autoturn_timeout_seconds", self.autoturn_sec)
  --      self.enabled = true
  --      G_reader_settings:makeTrue("autoturn_enabled")
  --      self:_unschedule()
  --      self:_start()
  --      menu:updateItems()
  --      self.onResume = self._onResume
  --    end,
  --  }
  --  UIManager:show(autoturn_spin)
  --end,
  --hold_callback = function(menu)
  --  local SpinWidget = require("ui/widget/spinwidget")
  --  local curr_items = G_reader_settings:readSetting("autoturn_distance") or 1
  --  local autoturn_spin = SpinWidget:new {
  --    value = curr_items,
  --    value_min = -20,
  --    value_max = 20,
  --    precision = "%.2f",
  --    value_step = .1,
  --    value_hold_step = .5,
  --    ok_text = _("Set distance"),
  --    title_text = _("Scrolling distance"),
  --    callback = function(autoturn_spin)
  --      self.autoturn_distance = autoturn_spin.value
  --      G_reader_settings:saveSetting("autoturn_distance", autoturn_spin.value)
  --      if self.enabled then
  --        self:_unschedule()
  --        self:_start()
  --      end
  --      menu:updateItems()
  --    end,
  --  }
  --  UIManager:show(autoturn_spin)
  --end,
  --}
end

function HardcoverApp:bookSearchList()

end

function HardcoverApp:getSubMenuItems()
  return {
    {
      text_func = function()
        if self:linked() then
          return _("Link book (already linked)")
        else
          return _("Link book")
        end
      end,
      callback = function()
        logger.warn("Opening container?")

        -- conditions: everything already linked

        -- book linked, but not edition
        --logger.warn(props)
        --if true then
        --  return nil
        --end
        local props = self.view.document:getProps()
        local identifiers = self:parseIdentifiers(props.identifiers)
        logger.warn(props, identifiers)
        local user_id = self:getUserId()
        -- TODO: what is format for props.authors

        local search_results = Api:findBook(props.title, props.authors, identifiers, user_id)
        logger.warn("Search", search_results)
        --local items
        --
        --if search_results.edition then
        --  -- only one edition, allow manual overriding (title search)
        --elseif search_results.books then
        --  items = search_results.books
        --end
        --
        -- different UI parent or different child?
        UIManager:show(SearchDialog:new { items = search_results.books })

        --self:bookSearchList()
      end,
    },
    {
      text = _("Track progress"),
      checked_func = function()
        return self:enabled()
      end,
      enabled_func = function()
        return self:linked()
      end,
      callback = function()
        if setting.sync then
          self:stopSync()
        else
          self:startSync()
        end
      end,
    },
    {
      text = _("Mark started"),
      enabled_func = function()
        return self:linked()
      end,
    },
    {
      text = _("Mark finished"),
      enabled_func = function()
        return self:linked()
      end,
    },
    {
      text = _("Mark to-read"),
      enabled_func = function()
        return self:linked()
      end,
    },
    {
      text = _("Mark did-not-finish"),
      enabled_func = function()
        return self:linked()
      end,
    }
  }
end

return HardcoverApp
