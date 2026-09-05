local logger = require("logger")
local http = require("socket.http")
local ltn12 = require("ltn12")
local url = require("socket.url")
local socketutil = require("socketutil")

local json = require("json")
local Trapper = require("ui/trapper")

local user_agent = require("hardcover/lib/user_agent")
local OAUTH = require("hardcover/lib/constants/oauth")

local OAuthClient = {}

local function form_encode(fields)
  local parts = {}
  for k, v in pairs(fields) do
    table.insert(parts, url.escape(k) .. "=" .. url.escape(v))
  end
  return table.concat(parts, "&")
end

local function post_form(path, fields)
  local body = form_encode(fields)
  local sink = {}
  socketutil:set_timeout(6, 15)
  local _, code = http.request({
    url = OAUTH.API_BASE .. path,
    method = "POST",
    headers = {
      ["Content-Type"] = "application/x-www-form-urlencoded",
      ["Content-Length"] = tostring(#body),
      ["User-Agent"] = user_agent,
    },
    source = ltn12.source.string(body),
    sink = socketutil.table_sink(sink),
  })
  socketutil:reset_timeout()
  return tostring(code) .. ":" .. table.concat(sink)
end

-- Each of these blocks on network I/O. Call from `Trapper:dismissableRunInSubprocess`

function OAuthClient:_requestDeviceCode()
  return post_form(OAUTH.DEVICE_ENDPOINT, { client_id = OAUTH.CLIENT_ID, scope = OAUTH.SCOPES })
end

function OAuthClient:_pollToken(device_code)
  return post_form(OAUTH.TOKEN_ENDPOINT, {
    grant_type = "urn:ietf:params:oauth:grant-type:device_code",
    device_code = device_code,
    client_id = OAUTH.CLIENT_ID,
  })
end

function OAuthClient:_refresh(refresh_token)
  return post_form(OAUTH.TOKEN_ENDPOINT, {
    grant_type = "refresh_token",
    refresh_token = refresh_token,
    client_id = OAUTH.CLIENT_ID,
  })
end

function OAuthClient:refresh(refresh_token)
  local completed, raw = Trapper:dismissableRunInSubprocess(function()
    return self:_refresh(refresh_token)
  end, false, true)

  if not completed or not raw then
    return nil, "network_error"
  end

  local code, body = raw:match("^([^:]*):(.*)")
  if not (code and code:match("^%d%d%d")) then
    return nil, "network_error"
  end

  local ok, data = pcall(json.decode, body, json.decode.simple)
  data = (ok and type(data) == "table") and data or {}

  if code:match("^2%d%d") and data.access_token then
    return data
  elseif code == "400" or code == "401" or data.error == "invalid_grant" or data.error == "invalid_token" or data.error == "expired_token" then
    return nil, "rejected", data
  else
    return nil, "error", data
  end
end

function OAuthClient:_revoke(token, token_type_hint)
  return post_form(OAUTH.REVOKE_ENDPOINT, {
    token = token,
    token_type_hint = token_type_hint,
    client_id = OAUTH.CLIENT_ID,
  })
end

return OAuthClient
