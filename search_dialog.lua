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
local SearchMenu = require("searchmenu")
local getUrlContent = require("vendor/url_content")
local RenderImage = require("ui/renderimage")

local DGENERIC_ICON_SIZE = G_defaults:readSetting("DGENERIC_ICON_SIZE")
local footer_height = DGENERIC_ICON_SIZE + Size.line.thick

local InputContainer = require("ui/widget/container/inputcontainer")

local HardcoverSearchDialog = InputContainer:extend {
  width = nil,
  bordersize = Size.border.window,
  items = {}
}

local function loadImage(url)
  local success, content
  -- Smaller timeout than when we have a trap_widget because we are
  -- blocking without one (but 20s may be needed to fetch the main HTML
  -- page of big articles when making an EPUB).
  local timeout, maxtime = 10, 20
  success, content = getUrlContent(url, timeout, maxtime)

  return success, content
end

function HardcoverSearchDialog:bookItem(book)
  local info = ""
  local title = book.title
  local authors = {}

  if book.contributions.author then
    table.insert(authors, book.contributions.author)
  end

  if #book.contributions > 0 then
    for _, a in ipairs(book.contributions) do
      table.insert(authors, a.author.name)
    end
  end

  if book.release_year then
    title = title .. " (" .. book.release_year  .. ")"
  end

  if book.users_read_count then
    info = book.users_read_count .. " reads"
  end

  local result = {
    title = title,

    mandatory = info,
    mandatory_dim = true,
    file = "hardcover-" .. book.id,
    _no_provider = true,
  }

  if book.pages then
    result.pages = book.pages
  end

  if book.book_series.position then
    result.series = book.book_series.series.name
    result.series_index = book.book_series.position
  end

  if #authors > 0 then
    result.authors = table.concat(authors, "\n")
  end

  if book.cached_image.url then
    local status, cover_data = loadImage(book.cached_image.url)
    if status then
      result.cover_w = book.cached_image.width
      result.cover_h = book.cached_image.height
      result.has_cover = true
      result.cover_bb = RenderImage:renderImageData(cover_data, #cover_data, false, result.cover_w, result.cover_h)
    end

    return result
  end
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
  --logger.warn("dialog", self.items)
  for _, book in ipairs(self.items) do
    table.insert(items, self:bookItem(book))
  end

  self.width = self.width or Screen:getWidth() - Screen:scaleBySize(50)
  self.width = math.min(self.width, Screen:scaleBySize(600))
  self.height = Screen:getHeight() - Screen:scaleBySize(50)


  self.menu = SearchMenu:new {
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

function HardcoverSearchDialog:menu_init()
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
  --logger.warn("dialog", self.items)
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

function HardcoverSearchDialog:onClose()
  UIManager:close(self)
  return true
end

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
