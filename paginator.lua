local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local _ = require("gettext")

local chevron_left = "chevron.left"
local chevron_right = "chevron.right"
local chevron_first = "chevron.first"
local chevron_last = "chevron.last"

local MinimalPaginator = InputContainer:extend{
  width = nil,
  height = nil,
  pages = nil,
  current_page = nil,
  go_to_page_cb = nil,
}

function MinimalPaginator:init()
  --self.width = 200
  self.dimen = self:getSize()

  self.left = Button:new{
    icon = chevron_left,
    width = self.footer_button_width,
    callback = function()
      if self.page > 1 then
        self.go_to_page_cb(self.current_page - 1)
      end
    end,
    bordersize = 0,
    radius = 0,
    show_parent = self,
  }

  self.right = Button:new{
    icon = chevron_right,
    width = self.footer_button_width,
    callback = function()
      if self.current_page < self.pages then
        self.go_to_page_cb(self.pages)
      end
    end,
    bordersize = 0,
    radius = 0,
    show_parent = self,
  }

  self.first = Button:new{
    icon = chevron_first,
    width = self.footer_button_width,
    callback = function()
      if self.current_page > 1 then
        self:go_to_page_cb(1)
      end
    end,
    bordersize = 0,
    radius = 0,
    show_parent = self,
  }

  self.last = Button:new{
    icon = chevron_last,
    width = self.footer_button_width,
    callback = function()
      if self.current_page < self.pages then
        self:go_to_page_cb(self.pages)
      end
    end,
    bordersize = 0,
    radius = 0,
    show_parent = self,
  }

  self.page_text = Button:new{
    text_func = function()
      return string.format("Page %s of %s", self.current_page, self.pages)
    end,
    hold_input = {
      title = _("Enter page number"),
      input_type = "number",
      hint_func = function()
        return string.format("(1 - %s)", self.pages)
      end,
      callback = function(input)
        local page = tonumber(input)
        if page and page >= 1 and page <= self.pages then
          if page ~= self.current_page then
            self:go_to_page_cb(page)
          end
        end
      end,
      ok_text = _("Go to page"),
    },
    call_hold_input_on_tap = true,
    bordersize = 0,
    margin = 0,
    text_font_face = "pgfont",
    text_font_bold = false,
    width = self.footer_center_width,
    show_parent = self,
  }

  self.page_info = HorizontalGroup:new{
    align = "center",
    bordersize = 1,
    self.first,
    self.left,
    self.page_text,
    self.right,
    self.last,

  }

  self[1] = FrameContainer:new{
    --height = self.dimen.h,
    --width = self.dimen.w,
    padding = 0,
    bordersize = 0,
    background = Blitbuffer.COLOR_WHITE,
    self.page_info,
    TextWidget:new {
      text = "pagination?",
      face = Font:getFace("cfont", 14)
    }
  }
end

function MinimalPaginator:getSize()
  return Geom:new{w = self.width, h = self.height}
end

function MinimalPaginator:setProgress(page, total_pages)
  self.current_page = page
  self.pages = total_pages

  self.page_text:setText(self.page_text:text_func(), self.page_text.width)
end

return MinimalPaginator
