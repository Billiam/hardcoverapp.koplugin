local SETTING = require("hardcover/lib/constants/settings")

local Device = require("device")
local logger = require("logger")

local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local Notification = require("ui/widget/notification")

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
    --UIManager:show(Notification:new {
    --  text = "Enabling wifi"
    --})

    NetworkMgr:restoreWifiAsync()
    NetworkMgr:scheduleConnectivityCheck(function()
      self.connection_pending = false
      UIManager:show(Notification:new {
        text = "Connection active"
      })

      callback()

      -- TODO: schedule turn off wifi, debounce
      NetworkMgr:turnOffWifi()
      --NetworkMgr:turnOffWifi(function()
      --  UIManager:show(Notification:new {
      --    text = "Disabled wifi"
      --  })
      --end)
    end)
  end
end

return AutoWifi
