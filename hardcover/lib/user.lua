local SETTING = require("hardcover/lib/constants/settings")
local Api = require("hardcover/lib/hardcover_api")

local User = {}

function User:_set_me(me)
  if not me then
    me = { }
  end

  self.settings:updateSetting(SETTING.USER_ID, me.id)
  self.settings:updateSetting(SETTING.NAME, me.name)
  self.settings:updateSetting(SETTING.USERNAME, me.username)
end

function User:getId()
  local user_id = self.settings:readSetting(SETTING.USER_ID)
  if not user_id then
    local me = Api:me()
    self:_set_me(me)
    user_id = me.id
  end

  return user_id
end

function User:getName()
  return self.settings:readSetting(SETTING.NAME)
end

function User:getUsername()
  return self.settings:readSetting(SETTING.USERNAME)
end

return User
