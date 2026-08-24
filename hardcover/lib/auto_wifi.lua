local SETTING = require("hardcover/lib/constants/settings")

local Device = require("device")

local NetworkMgr = require("ui/network/manager")
local socket = require("socket")
local UIManager = require("ui/uimanager")

local api_host = "api.hardcover.app"
local dns_attempts = 6

local function waitForDNS(host, attempts, callback)
  local ip = socket.dns.toip(host)

  if ip then
    callback(true)
    return
  end

  if attempts <= 0 then
    callback(false)
    return
  end

  UIManager:scheduleIn(5, function()
    waitForDNS(host, attempts - 1, callback)
  end)
end

local AutoWifi = {
  connection_pending = false
}
AutoWifi.__index = AutoWifi

function AutoWifi:new(o)
  return setmetatable(o, self)
end

function AutoWifi:withWifi(callback)
  if NetworkMgr:isWifiOn() then
    callback(false)
    return
  end

  if self.settings:readSetting(SETTING.ENABLE_WIFI)
      and not NetworkMgr.pending_connection
      and Device:hasWifiRestore()
      and G_reader_settings:nilOrFalse("airplanemode") then
    --logger.warn("HARDCOVER enabling wifi")

    local original_on = NetworkMgr.wifi_was_on

    NetworkMgr:restoreWifiAsync()
    NetworkMgr:scheduleConnectivityCheck(function()
      -- restore original "was on" state to prevent wifi being restored automatically after suspend
      NetworkMgr.wifi_was_on = original_on
      G_reader_settings:saveSetting("wifi_was_on", original_on)

      self.connection_pending = false

      -- Wait for Hardcover's DNS to become available before making API requests.
      waitForDNS(api_host, dns_attempts, function(ready)
        if ready then
          callback(true)
        end

        -- TODO: schedule turn off wifi, debounce
        self:wifiDisableSilent()
      end)
    end)
  end
end

function AutoWifi:wifiDisableSilent()
  NetworkMgr:turnOffWifi(function()
    -- explicitly disable wifi was on
    NetworkMgr.wifi_was_on = false
    G_reader_settings:saveSetting("wifi_was_on", false)
    --logger.warn("HARDCOVER disabling wifi")
  end)
end

function AutoWifi:wifiPrompt(callback)
  if NetworkMgr:isWifiOn() then
    if callback then
      callback(false)
    end

    return
  end

  if G_reader_settings:isTrue("airplanemode") then
    return
  end

  local network_callback = callback and function()
    callback(true)
  end or nil

  if self.settings:readSetting(SETTING.ENABLE_WIFI) then
    NetworkMgr:turnOnWifiAndWaitForConnection(network_callback)
  else
    NetworkMgr:promptWifiOn(network_callback)
  end
end

function AutoWifi:wifiDisablePrompt()
  if self.settings:readSetting(SETTING.ENABLE_WIFI) and Device:hasWifiRestore() then
    self:wifiDisableSilent()
  else
    NetworkMgr:toggleWifiOff()
  end
end

return AutoWifi