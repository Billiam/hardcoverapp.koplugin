local config = require("hardcover_config")
local http = require("socket.http")
local json = require("json")
local ltn12 = require("ltn12")
local socket_url = require("socket.url")
local socketutil = require("socketutil")

local NetworkManager = require("ui/network/manager")
local Trapper = require("ui/trapper")

local Book = require("hardcover/lib/book")
local SETTING = require("hardcover/lib/constants/settings")

local api_url = "https://www.aladin.co.kr/ttb/api/ItemSearch.aspx"

local AladinApi = {
  enabled = true,
  settings = nil,
}

local function configuredKey()
  local key
  if AladinApi.settings then
    key = AladinApi.settings:readSetting(SETTING.ALADIN_TTB_KEY)
  end
  if key == nil or key == "" then
    key = config.aladin_ttb_key
  end

  if type(key) ~= "string" then
    return
  end

  key = key:match("^%s*(.-)%s*$")
  if key == "" or key == "your Aladin TTB key here" then
    return
  end

  return key
end

local function queryString(parameters)
  local parts = {}
  local names = {}

  for name, _ in pairs(parameters) do
    table.insert(names, name)
  end
  table.sort(names)

  for _, name in ipairs(names) do
    table.insert(parts, socket_url.escape(name) .. "=" .. socket_url.escape(tostring(parameters[name])))
  end

  return table.concat(parts, "&")
end

local function normalizeItem(item)
  if type(item) ~= "table" then
    return
  end

  local isbn_13 = Book:normalizeIsbn(item.isbn13)
  local isbn_10 = Book:normalizeIsbn(item.isbn)
  if not isbn_13 and not isbn_10 then
    return
  end

  return {
    author = item.author,
    cover = item.cover,
    isbn_10 = isbn_10,
    isbn_13 = isbn_13,
    link = item.link,
    mall_type = item.mallType,
    pub_date = item.pubDate,
    publisher = item.publisher,
    title = item.title,
  }
end

function AladinApi:isConfigured()
  return configuredKey() ~= nil
end

function AladinApi:getKey()
  return configuredKey()
end

function AladinApi:_request(parameters)
  local sink = {}
  socketutil:set_timeout(6, 12)

  local _, code = http.request {
    url = api_url .. "?" .. queryString(parameters),
    method = "GET",
    headers = {
      ["User-Agent"] = "hardcoverapp.koplugin Aladin search"
    },
    sink = socketutil.table_sink(sink),
  }

  socketutil:reset_timeout()
  return code .. ":" .. table.concat(sink)
end

function AladinApi:_searchTarget(query, target)
  local key = configuredKey()
  if not key then
    return nil, { aladin = "missing_key" }
  end

  if not NetworkManager:isConnected() or not self.enabled then
    return nil, { completed = false }
  end

  local completed, content = Trapper:dismissableRunInSubprocess(function()
    return self:_request {
      Cover = "MidBig",
      MaxResults = 25,
      output = "js",
      Query = query,
      QueryType = "Keyword",
      SearchTarget = target,
      start = 1,
      ttbkey = key,
      Version = "20131101",
    }
  end, true, true)

  if not completed or not content then
    return nil, { completed = completed }
  end

  local code, response = content:match("^([^:]*):(.*)")
  if not code or not code:match("^2%d%d$") then
    return nil, { status = code }
  end

  local data = json.decode(response, json.decode.simple)
  if not data or data.errorCode then
    return nil, {
      aladin = data and data.errorCode or "invalid_response",
      message = data and data.errorMessage,
    }
  end

  local items = {}
  for _, item in ipairs(data.item or {}) do
    local normalized = normalizeItem(item)
    if normalized then
      table.insert(items, normalized)
    end
  end

  return items
end

function AladinApi:search(title, author)
  local query = title
  if author and author ~= "" then
    query = query .. " " .. author
  end

  local results = {}
  local seen = {}
  local first_error

  -- KOReader predominantly opens EPUBs, so prefer Aladin's ebook result when
  -- the same Korean title is available in both electronic and print formats.
  for _, target in ipairs({ "eBook", "Book" }) do
    local items, err = self:_searchTarget(query, target)
    if err and not first_error then
      first_error = err
    end

    for _, item in ipairs(items or {}) do
      local key = item.isbn_13 or item.isbn_10
      if not seen[key] then
        seen[key] = true
        table.insert(results, item)
      end
    end
  end

  if #results == 0 and first_error then
    return nil, first_error
  end

  return results
end

return AladinApi
