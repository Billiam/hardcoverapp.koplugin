local SETTING = require("hardcover/lib/constants/settings")

local Device = require("device")
local logger = require("logger")

local NetworkMgr = require("ui/network/manager")

local AutoWifi = {
  connection_pending = false
}
AutoWifi.__index = AutoWifi

function AutoWifi:new(o)
  return setmetatable(o, self)
end

function AutoWifi:withWifi(callback)
  if NetworkMgr:isWifiOn() then
    callback()
    return
  end

  if self.settings:readSetting(SETTING.ENABLE_WIFI) and not NetworkMgr.pending_connection and Device:hasWifiRestore() then
    --logger.warn("HARDCOVER enabling wifi")

    NetworkMgr:restoreWifiAsync()
    NetworkMgr:scheduleConnectivityCheck(function()
      self.connection_pending = false
      --logger.warn("HARDCOVER wifi enabled")

      callback()

      -- TODO: schedule turn off wifi, debounce
      NetworkMgr:turnOffWifi()
      --NetworkMgr:turnOffWifi(function()
      --  logger.warn("HARDCOVER disabling wifi")
      --end)
    end)
  end
end

return AutoWifi
