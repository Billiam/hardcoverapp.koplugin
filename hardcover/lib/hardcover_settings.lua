local KoreaderVersion = require("version")
local LuaSettings = require("luasettings")

local SETTING = require("hardcover/lib/constants/settings")

local HardcoverSettings = {}
HardcoverSettings.__index = HardcoverSettings

function HardcoverSettings:new(path, ui)
  local o = {}
  setmetatable(o, self)

  self.settings = LuaSettings:open(path)
  self.ui = ui
  self.subscribers = {}

  if KoreaderVersion:getNormalizedCurrentVersion() < 202403010000 then
    if self.settings:readSetting(SETTING.COMPATIBILITY_MODE) == nil then
      self:updateSetting(SETTING.COMPATIBILITY_MODE, true)
    end
  end

  return o
end

function HardcoverSettings:readSetting(key)
  return self.settings:readSetting(key)
end

function HardcoverSettings:readBookSettings(filename)
  local books = self.settings:readSetting("books")
  if not books then
    return {}
  end

  return books[filename]
end

function HardcoverSettings:readBookSetting(filename, key)
  local settings = self:readBookSettings(filename)
  if settings then
    return settings[key]
  end
end

function HardcoverSettings:updateBookSetting(filename, config)
  local books = self.settings:readSetting("books", {})
  if not books[filename] then
    books[filename] = {}
  end
  local book_setting = books[filename]
  local original_value = { table.unpack(book_setting) }
  for k, v in pairs(config) do
    if k == "_delete" then
      for _, name in ipairs(v) do
        book_setting[name] = nil
      end
    else
      book_setting[k] = v
    end
  end

  self.settings:flush()

  self:notify(SETTING.BOOKS, { filename = filename, config = config }, original_value)
end

function HardcoverSettings:updateSetting(key, value)
  local original_value = self.settings:readSetting(key)
  self.settings:saveSetting(key, value)

  self.settings:flush()

  self:notify(key, value, original_value)
end

function HardcoverSettings:notify(key, value, original_value)
  for _, cb in ipairs(self.subscribers) do
    cb(key, value, original_value)
  end
end

function HardcoverSettings:subscribe(cb)
  table.insert(self.subscribers, cb)
end

function HardcoverSettings:unsubscribe(cb)
  local new_subscribers = {}
  for _, original_cb in ipairs(self.subscribers) do
    if original_cb ~= cb then
      table.insert(new_subscribers, original_cb)
    end
  end
  self.subscribers = new_subscribers
end

function HardcoverSettings:setSync(value)
  self:updateBookSetting(self.ui.document.file, { sync = value == true })
end

function HardcoverSettings:setTrackMethod(method)
  self:updateSetting(SETTING.TRACK_METHOD, method)
end

function HardcoverSettings:editionLinked()
  return self:getLinkedEditionId() ~= nil
end

function HardcoverSettings:readLinked()
  return self:readBookSetting(self.ui.document.file, "read_id") ~= nil
end

function HardcoverSettings:bookLinked()
  return self:getLinkedBookId() ~= nil
end

function HardcoverSettings:getLinkedTitle()
  return self:readBookSetting(self.ui.document.file, "title")
end

function HardcoverSettings:getLinkedBookId()
  return self:readBookSetting(self.ui.document.file, "book_id")
end

function HardcoverSettings:getLinkedEditionFormat()
  return self:readBookSetting(self.ui.document.file, "edition_format")
end

function HardcoverSettings:getLinkedEditionId()
  return self:readBookSetting(self.ui.document.file, "edition_id")
end

function HardcoverSettings:fileSyncEnabled(file)
  local sync_value = self:readBookSetting(file, "sync")
  if sync_value == nil then
    sync_value = self.settings:readSetting(SETTING.ALWAYS_SYNC)
  end
  return sync_value == true
end

function HardcoverSettings:syncEnabled()
  return self:fileSyncEnabled(self.ui.document.file)
end

function HardcoverSettings:autolinkEnabled()
  for _, setting in ipairs(SETTING.AUTOLINK_OPTIONS) do
    if self.settings:readSetting(setting) then
      return true
    end
  end

  return false
end

function HardcoverSettings:pages()
  return self:readBookSetting(self.ui.document.file, "pages")
end

function HardcoverSettings:trackFrequency()
  return self.settings:readSetting(SETTING.TRACK_FREQUENCY) or 5
end

function HardcoverSettings:trackPercentageInterval()
  return self.settings:readSetting(SETTING.TRACK_PERCENTAGE) or 10
end

function HardcoverSettings:trackByTime()
  local setting = self.settings:readSetting(SETTING.TRACK_METHOD)
  return setting == nil or setting == SETTING.TRACK.FREQUENCY
end

function HardcoverSettings:trackByProgress()
  return self.settings:readSetting(SETTING.TRACK_METHOD) == SETTING.TRACK.PROGRESS
end

function HardcoverSettings:changeTrackPercentageInterval(percent)
  self:updateSetting(SETTING.TRACK_PERCENTAGE, percent)
end

function HardcoverSettings:compatibilityMode()
  return self.settings:readSetting(SETTING.COMPATIBILITY_MODE) == true
end

return HardcoverSettings
