local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderImage = require("ui/renderimage")
local SearchMenu = require("searchmenu")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local getUrlContent = require("vendor/url_content")
local logger = require("logger")

local Screen = Device.screen

local HardcoverSearchDialog = InputContainer:extend {
  width = nil,
  bordersize = Size.border.window,
  items = {},
  active_item = {},
  select_cb = nil,
  title = nil
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

function HardcoverSearchDialog:createListItem(book, active_item)
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

  if book.users_count then
    info = book.users_count .. " readers"
  elseif  book.users_read_count then
    info = book.users_read_count .. " reads"
  end

  local active = (book.edition_id and book.edition_id == active_item.edition_id) or (book.id == active_item.book_id)

  local result = {
    title = title,
    mandatory = info,
    mandatory_dim = true,
    file = "hardcover-" .. book.id,
    book_id = book.id,
    edition_id = book.edition_id,
    edition_format = book.edition_format,
    highlight = active,
  }

  if book.pages then
    result.pages = book.pages
  end

  if book.book_series.position then
    result.series = book.book_series.series.name
    result.series_index = book.book_series.position
  end

  if #authors > 0 then
    result.authors = table.concat(authors, ", ")
  end

  if book.filetype then
    result.filetype = book.filetype
  end

  if book.cached_image.url then
    result.cover_url = book.cached_image.url
    result.cover_w = book.cached_image.width
    result.cover_h = book.cached_image.height
    result.lazy_load_cover = true
  end

  return result
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

  self.width = self.width or Screen:getWidth() - Screen:scaleBySize(50)
  self.width = math.min(self.width, Screen:scaleBySize(600))
  self.height = Screen:getHeight() - Screen:scaleBySize(50)

  self.menu = SearchMenu:new {
    title = self.title or "Select book",
    item_table = self:parseItems(self.items, self.active_item),
    width = self.width,
    height = self.height,
    onMenuSelect = function(menu, book)
      if self.select_book_cb then
        self.select_book_cb(book)
      end
    end,
    close_callback = function()
      self:onClose()
    end
  }

  self.items = nil

  self.container = CenterContainer:new{
    dimen = Screen:getSize(),
    self.menu,
  }

  self.menu.show_parent = self

  self[1] = self.container
end

function HardcoverSearchDialog:setTitle(title)
  self.menu.title = title
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

function HardcoverSearchDialog:parseItems(items, active_item)
  local list = {}
  for _, book in ipairs(items) do
    table.insert(list, self:createListItem(book, active_item))
  end
  return list
end

function HardcoverSearchDialog:setItems(title, items, active_item)
  -- hack: Allow reusing menu (and closing more than once)
  self.menu._covermenu_onclose_done = false
  local new_item_table = self:parseItems(items, active_item)
  if self.menu.item_table then
    for _,v in ipairs(self.menu.item_table) do
      if v.cover_bb then
        v.cover_bb:free()
      end
    end
  end
  self.menu:switchItemTable(title, new_item_table)
end

function HardcoverSearchDialog:onTap(_, ges)
  if ges.pos:notIntersectWith(self[1][1].dimen) then
    -- Tap outside closes widget
    self:onClose()
    return true
  end
end

return HardcoverSearchDialog
