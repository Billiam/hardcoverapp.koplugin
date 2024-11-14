local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ListView = require("ui/widget/listview")
local Font = require("ui/font")
local Paginator = require("paginator")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local GestureRange = require("ui/gesturerange")
local Screen = Device.screen
local Menu = require("ui/widget/menu")
local logger = require("logger")


local DGENERIC_ICON_SIZE = G_defaults:readSetting("DGENERIC_ICON_SIZE")
local footer_height = DGENERIC_ICON_SIZE + Size.line.thick

local InputContainer = require("ui/widget/container/inputcontainer")

local HardcoverSearchDialog = InputContainer:extend {
  width = nil,
  bordersize = Size.border.window,
  items = {}
}

--function HardcoverSearchDialog:bookItem(book)
--  local face = Font:getFace("cfont", 14)
--
--  return TextWidget:new {
--    text = book.title,
--    face = face
--  }
--end

function HardcoverSearchDialog:bookItem(book)
  local info = ""
  local title = book.title

  if book.contributions.author then
    title = title .. " - " .. book.contributions.author.name
  end

  if #book.contributions > 0 then
    local names = {}
    for _, a in ipairs(book.contributions) do
      table.insert(names, a.author.name)
    end

    title = title .. " - " .. table.concat(names, ", ")
  end
  if type(book.release_year) == "number" then
    title = title .. " (" .. book.release_year  .. ")"
  end

  if book.users_read_count then
    info = book.users_read_count .. " reads"
  end

  return {
    text = title,
    mandatory = info,
    mandatory_dim = true,
  }
end

function HardcoverSearchDialog:init()
  if Device:isTouchDevice() then
    self.ges_events.Tap = {
      GestureRange:new {
        ges = "tap",
        range = Geom:new {
          x = 0,
          y = 0,
          w = Screen:getWidth(),
          h = Screen:getHeight(),
        }
      }
    }
  end

  local items = {}
  logger.warn("dialog", self.items)
  for _, book in ipairs(self.items) do
    table.insert(items, self:bookItem(book))
  end

  self.width = self.width or Screen:getWidth() - Screen:scaleBySize(50)
  self.width = math.min(self.width, Screen:scaleBySize(600))
  self.height = Screen:getHeight() - Screen:scaleBySize(50)

  self.menu = Menu:new {
    title = "Select book",
    item_table = items,
    width = self.width,
    height = self.height,

    --title_bar_fm_style = true,
    --is_popout = true,
    onMenuSelect = function(item, pos)
      logger.warn("selected: ", pos)
    end,
    close_callback = function()
      self:onClose()
    end
  }

  self.container = CenterContainer:new{
    dimen = Screen:getSize(),
    self.menu,
  }
  self.menu.show_parent = self.container

  self[1] = self.container
end


function HardcoverSearchDialog:init_old()
  if Device:hasKeys() then
    self.key_events.Close = { { Device.input.group.Back } }
  end
  if Device:isTouchDevice() then
    self.ges_events.Tap = {
      GestureRange:new {
        ges = "tap",
        range = Geom:new {
          x = 0,
          y = 0,
          w = Screen:getWidth(),
          h = Screen:getHeight(),
        }
      }
    }
  end

  local items = {}
  logger.warn("dialog", self.items)
  for _, book in ipairs(self.items) do


    table.insert(items, self:bookItem(book))
  end

  -- build

  --local label_widget = TextWidget:new {
  --  text = "label",
  --  face = Font:getFace("cfont", 14)
  --}

  self.width = self.width or Screen:getWidth() - Screen:scaleBySize(50)
  self.width = math.min(self.width, Screen:scaleBySize(600))
  self.height = self.height or math.min(Screen:getHeight()*3/4,
      Screen:scaleBySize(800))

  self.pagination = Paginator:new{
    width = self.width,
    height = footer_height,
    percentage = 0,
    progress = 0,
  }

  self.title_bar = TitleBar:new{
    width = self.width,
    align = "left",
    with_bottom_line = true,
    title = "Search results",
    title_multilines = true,
    bottom_v_padding = self.bottom_v_padding,
    info_text = "Select book",
    --left_icon = self.title_bar_left_icon,
    --left_icon_tap_callback = self.title_bar_left_icon_tap_callback,
    close_callback = function() self:onClose() end,
    show_parent = self,
  }

  self[1] = CenterContainer:new {
    dimen = { w = Screen:getWidth(), h = Screen:getHeight() },
    close_callback = function() self:onClose() end,
    FrameContainer:new {
      margin = 0,
      background = Blitbuffer.COLOR_WHITE,
      radius = Size.radius.default,
      padding = 0,
      bordersize = self.bordersize,
      VerticalGroup:new{
        align = "left",
        self.title_bar,
        ListView:new{
          padding = 0,
          items = items,
          width = self.width,
          height = self.height - self.pagination:getSize().h,
          page_update_cb = function(curr_page, total_pages)
            logger.warn("Pages", curr_page, total_pages)
            self.pagination:setProgress(curr_page, total_pages)
            --self.page_text:setText(curr_page .. "/" .. total_pages)
            UIManager:setDirty(self, function()
              return "ui", self.dimen
            end)
          end
        },
        self.pagination
      }
    }
  }
  --self.dimen = Geom:new {
  --  x = 0,
  --  y = 0,
  --  w = self.width,
  --  h = self.height,
  --}
end

--
--self.pagination = Paginator:new{
--  width = self.width,
--  height = Screen:scaleBySize(8),
--  percentage = 0,
--  progress = 0,
--}
--
--self.popup = FrameContainer:new{
--  background = Blitbuffer.COLOR_WHITE,
--  padding = 0,
--  bordersize = Size.border.window,
--  VerticalGroup:new{
--    align = "left",
--    --self.pagination,
--    --ListView:new{
--    --  padding = 0,
--    --  items = self.state.search_results,
--    --  width = self.width,
--    --  height = self.height-self.pagination:getSize().h,
--    --  page_update_cb = function(curr_page, total_pages)
--    --    --self.pagination:setProgress(curr_page/total_pages)
--    --    ---- self.page_text:setText(curr_page .. "/" .. total_pages)
--    --    --UIManager:setDirty(self, function()
--    --    --  return "ui", self.popup.dimen
--    --    --end)
--    --  end
--    --},
--  },
--}
--
--self.main_container = CenterContainer:new {
--  dimen = { w = Screen:getWidth(), h = Screen:getHeight() },
--  self.popup
--}

--
--function ButtonDialog:onCloseWidget()
--  UIManager:setDirty(nil, function()
--    return "flashui", self.movable.dimen
--  end)
--end

function HardcoverSearchDialog:onClose()
  UIManager:close(self)
  return true
end
--function HardcoverSearchDialog:onCloseWidget()
--  UIManager:close(self)
--  return true
--end

function HardcoverSearchDialog:onTapClose(arg, ges)
  if ges.pos:notIntersectWith(self.movable.dimen) then
    self:onClose()
  end
  return true
end


function HardcoverSearchDialog:onTap(_, ges)
  if ges.pos:notIntersectWith(self[1][1].dimen) then
    -- Tap outside closes widget
    self:onClose()
    return true
  end
end



return HardcoverSearchDialog
