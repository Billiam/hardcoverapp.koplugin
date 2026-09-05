local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local ButtonDialog = require("ui/widget/buttondialog")
local QRMessage = require("ui/widget/qrmessage")
local Device = require("device")
local ffiutil = require("ffi/util")
local json = require("json")
local math = require("math")
local os = require("os")
local T = require("ffi/util").template
local _ = require("gettext")

local OAuthClient = require("hardcover/lib/oauth_client")

local DeviceAuthDialog = {}
DeviceAuthDialog.__index = DeviceAuthDialog

function DeviceAuthDialog:new(o)
  return setmetatable(o or {}, self)
end

function DeviceAuthDialog:show(on_success, on_error)
  self.on_success = on_success
  self.on_error = on_error
  Trapper:wrap(function()
    self:_run()
  end)
end

function DeviceAuthDialog:_run()
  local completed, raw = Trapper:dismissableRunInSubprocess(function()
    return OAuthClient:_requestDeviceCode()
  end, _("Contacting Hardcover…"), true)

  if not completed then
    -- user dismissed the loading message
    return
  end

  local code, body = raw:match("^([^:]*):(.*)")
  if not (code and code:match("^2%d%d")) then
    if self.on_error then
      self.on_error(_("Could not start sign-in"))
    end
    return
  end

  local ok, device_auth = pcall(json.decode, body, json.decode.simple)
  if not ok or type(device_auth) ~= "table" or not device_auth.device_code then
    if self.on_error then
      self.on_error(_("Could not start sign-in"))
    end
    return
  end
  self.interval = tonumber(device_auth.interval) or 5
  local expires_at = os.time() + (tonumber(device_auth.expires_in) or 600)
  self.cancelled = false

  self:_buildDialog(device_auth)
  UIManager:show(self.dialog)

  while not self.cancelled and os.time() < expires_at do
    local poll_completed, poll_raw = Trapper:dismissableRunInSubprocess(function()
      ffiutil.sleep(self.interval)
      return OAuthClient:_pollToken(device_auth.device_code)
    end, self.dialog, true)

    if not poll_completed then
      -- Cancel button fired dismiss_callback
      break
    end

    local poll_code, poll_body = poll_raw:match("^([^:]*):(.*)")
    local poll_ok, data = pcall(json.decode, poll_body, json.decode.simple)
    data = (poll_ok and type(data) == "table") and data or {}

    if poll_code and poll_code:match("^2%d%d") and data.access_token then
      self:_close()
      if self.on_success then
        self.on_success(data)
      end
      return
    elseif data.error == "authorization_pending" then
      -- keep polling
    elseif data.error == "slow_down" then
      self.interval = self.interval + 5
    elseif data.error == "access_denied" then
      self:_close()
      if self.on_error then
        self.on_error(_("Sign-in was denied"))
      end
      return
    elseif data.error == "expired_token" then
      break
    else
      -- transient/network hiccup: back off rather than aborting outright
      self.interval = math.min(self.interval + 5, 30)
    end
  end

  self:_close()
  if not self.cancelled and self.on_error then
    self.on_error(_("Sign-in code expired"))
  end
end

function DeviceAuthDialog:_close()
  if self.qr_widget then
    UIManager:close(self.qr_widget)
    self.qr_widget = nil
  end
  UIManager:close(self.dialog)
end

function DeviceAuthDialog:_buildDialog(device_auth)
  self.dialog = ButtonDialog:new({
    title = T(
      _("Go to:\n%1\n\nand enter this code:\n\n%2\n\nWaiting for approval…"),
      device_auth.verification_uri,
      device_auth.user_code
    ),
    dismissable = false,
    buttons = {
      {
        {
          text = _("Show QR code"),
          callback = function()
            self.qr_widget = QRMessage:new({
              text = device_auth.verification_uri_complete,
              width = Device.screen:getWidth(),
              height = Device.screen:getHeight(),
              dismiss_callback = function()
                self.qr_widget = nil
              end,
            })
            UIManager:show(self.qr_widget)
          end,
        },
      },
      {
        {
          text = _("Cancel"),
          callback = function()
            self.cancelled = true
            if self.dialog.dismiss_callback then
              self.dialog.dismiss_callback()
            end
          end,
        },
      },
    },
  })
end

return DeviceAuthDialog
