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

    local original_on = NetworkMgr.wifi_was_on

    NetworkMgr:restoreWifiAsync()
    NetworkMgr:scheduleConnectivityCheck(function()
      -- restore original "was on" state to prevent wifi being restored automatically after suspend
      NetworkMgr.wifi_was_on = original_on
      G_reader_settings:saveSetting("wifi_was_on", original_on)

      self.connection_pending = false
      --logger.warn("HARDCOVER wifi enabled")

      callback()

      -- TODO: schedule turn off wifi, debounce
      NetworkMgr:turnOffWifi(function()
        -- explicitly disable wifi was on
        NetworkMgr.wifi_was_on = false
        G_reader_settings:saveSetting("wifi_was_on", false)
        --logger.warn("HARDCOVER disabling wifi")
      end)
    end)
  end
end

return AutoWifi
