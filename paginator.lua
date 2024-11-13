local Blitbuffer = require("ffi/blitbuffer")
local Widget = require("ui/widget/widget")
local Geom = require("ui/geometry")

local MinimalPaginator = Widget:extend{
  width = nil,
  height = nil,
  progress = nil,
}

function MinimalPaginator:getSize()
  return Geom:new{w = self.width, h = self.height}
end

function MinimalPaginator:paintTo(bb, x, y)
  self.dimen = self:getSize()
  self.dimen.x, self.dimen.y = x, y
  -- paint background
  bb:paintRoundedRect(x, y,
      self.dimen.w, self.dimen.h,
      Blitbuffer.COLOR_LIGHT_GRAY)
  -- paint percentage infill
  bb:paintRect(x, y,
      math.ceil(self.dimen.w*self.progress), self.dimen.h,
      Blitbuffer.COLOR_DARK_GRAY)
end

function MinimalPaginator:setProgress(progress) self.progress = progress end

return MinimalPaginator
