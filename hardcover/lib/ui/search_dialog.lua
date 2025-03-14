local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local SearchMenu = require("hardcover/lib/ui/search_menu")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local logger = require("logger")
local _t = require("hardcover/lib/table_util")

local Screen = Device.screen

local HardcoverSearchDialog = InputContainer:extend {
  width = nil,
  bordersize = Size.border.window,
  items = {},
  active_item = {},
  select_cb = nil,
  title = nil,
  search_callback = nil,
  search_value = nil,

  compatibility_mode = true
}

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
    title = title .. " (" .. book.release_year .. ")"
  end

  if book.users_count then
    info = book.users_count .. " readers"
  elseif book.users_read_count then
    info = book.users_read_count .. " reads"
  end

  local active = (book.edition_id and book.edition_id == active_item.edition_id) or (book.book_id == active_item.book_id)

  local result = {
    title = title,
    mandatory = info,
    mandatory_dim = true,
    file = "hardcover-" .. book.book_id,
    book_id = book.book_id,
    edition_id = book.edition_id,
    edition_format = book.edition_format,
    highlight = active,
  }

  if not book.edition_id and _t.dig(book, "book_series", 1, "position") then
    result.series = book.book_series[1].series.name
    if book.book_series[1].position then
      result.series = result.series .. " #" .. book.book_series[1].position
    end
  end

  if book.language and book.language.code2 then
    if self.series then
      result.series = " - " .. book.language.code2
    else
      result.series = book.language.language
    end
  end

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

  if self.compatibility_mode then
    result.text = result.title
    result.dim = result.highlight
    if book.edition_id then
      result.text = result.text .. " - " .. book.filetype
    else
      if result.authors and result.authors ~= "" then
        result.text = result.text .. " - " .. result.authors
      end
    end
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

  local left_icon, left_icon_callback
  if self.search_callback then
    left_icon = "appbar.search"
    left_icon_callback = function() self:search() end
  end
  local menu_class = self.compatibility_mode and Menu or SearchMenu

  self.menu = menu_class:new {
    single_line = false,
    multilines_show_more_text = true,
    title = self.title or "Select book",
    fullscreen = true,
    item_table = self:parseItems(self.items, self.active_item),
    width = self.width,
    height = self.height,
    title_bar_left_icon = left_icon,
    onLeftButtonTap = left_icon_callback,
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

  self.container = CenterContainer:new {
    dimen = Screen:getSize(),
    self.menu,
  }

  self.menu.show_parent = self

  self[1] = self.container
end

function HardcoverSearchDialog:search()
  local search_dialog
  search_dialog = InputDialog:new {
    title = "New search",
    input = self.search_value,
    save_button_text = "Search",
    buttons = { {
      {
        text = _("Cancel"),
        callback = function()
          UIManager:close(search_dialog)
        end,
      },
      {
        text = _("Search"),
        -- button with is_enter_default set to true will be
        -- triggered after user press the enter key from keyboard
        is_enter_default = true,
        callback = function()
          local text = search_dialog:getInputText()
          local result = self.search_callback(text)
          if result then
            UIManager:close(search_dialog)
          end
        end,
      }
    } }
  }

  UIManager:show(search_dialog)
  search_dialog:onShowKeyboard()
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
  if self.menu.halt_image_loading then
    self.menu.halt_image_loading()
  end

  -- hack: Allow reusing menu (and closing more than once)
  self.menu._covermenu_onclose_done = false
  local new_item_table = self:parseItems(items, active_item)
  if self.menu.item_table then
    for _, v in ipairs(self.menu.item_table) do
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
