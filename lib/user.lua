local SETTING = require("lib/constants/settings")
local Api = require("lib/hardcover_api")

local User = {}

function User:getId()
  local user_id = self.settings:readSetting(SETTING.USER_ID)
  if not user_id then
    local me = Api:me()
    user_id = me.id
    self.settings:updateSetting(SETTING.USER_ID, user_id)
  end

  return user_id
end

return User
