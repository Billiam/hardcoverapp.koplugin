local Menu = require("ui/widget/menu")
local ListMenu = require("vendor/listmenu")
local CoverMenu = require("vendor/covermenu")

local SearchMenu = Menu:extend{
  font_size = 22
}

SearchMenu.updateItems = CoverMenu.updateItems
SearchMenu.updateCache = CoverMenu.updateCache
SearchMenu.onCloseWidget = CoverMenu.onCloseWidget

SearchMenu._recalculateDimen = ListMenu._recalculateDimen
SearchMenu._updateItemsBuildUI = ListMenu._updateItemsBuildUI
-- Set ListMenu behaviour:
SearchMenu._do_cover_images = true
SearchMenu._do_filename_only = false
SearchMenu._do_hint_opened = false -- dogear at bottom


return SearchMenu
