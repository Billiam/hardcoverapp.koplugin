local Api = require("hardcover/lib/hardcover_api")
local User = require("hardcover/lib/user")

local Cache = {}
Cache.__index = Cache

function Cache:new(o)
  return setmetatable(o, self)
end

function Cache:updateBookStatus(filename, status, privacy_setting_id)
  local settings = self.settings:readBookSettings(filename)
  local book_id = settings.book_id
  local edition_id = settings.edition_id

  self.state.book_status = Api:updateUserBook(book_id, status, privacy_setting_id, edition_id) or {}
end

function Cache:cacheUserBook()
  local status, errors = Api:findUserBook(self.settings:getLinkedBookId(), User:getId())
  self.state.book_status = status or {}

  return errors
end

return Cache
