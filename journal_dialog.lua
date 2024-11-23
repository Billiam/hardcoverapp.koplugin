local Button = require("ui/widget/button")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputDialog = require("ui/widget/inputdialog")
local InputText = require("ui/widget/inputtext")
local Size = require("ui/size")
local SpinWidget = require("ui/widget/spinwidget")
local TextWidget = require("ui/widget/textwidget")
local ToggleSwitch = require("ui/widget/toggleswitch")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local logger = require("logger")

local JOURNAL_NOTE = "note"
local JOURNAL_QUOTE = "quote"

local JournalDialog = InputDialog:extend {
  allow_newline = true,
  text_height = 80,
  results = {},
  title = "Create journal entry",
  padding = 10,

  event_type = JOURNAL_NOTE,
  pages = _("???"),
  page = nil,
  edition_id = nil,
  edition_type = nil,
  tags = {},
  hidden_tags = {},
  privacy_setting_id = 1,
  select_edition_callback = nil
}

local function comma_split(text)
  local result = {}
  for str in string.gmatch(text, "([^,]+)") do
    local trimmed = str:match( "^%s*(.-)%s*$")
    if trimmed ~= "" then
      table.insert(result, trimmed)
    end
  end

  return result
end

function JournalDialog:init()
  self:setModified()

  self.save_callback = function()
    return self.save_dialog_callback({
      book_id = self.book_id,
      edition_id = self.edition_id,
      text = self.input,
      page = self.page,
      pages = self.pages,
      event_type = self.event_type,
      privacy_setting_id = self.privacy_setting_id,
      tags = comma_split(self.tag_field.text),
      hidden_tags = comma_split(self.hidden_tag_field.text)
    })
  end

  InputDialog.init(self)

  local journal_type
  journal_type = ToggleSwitch:new{
    width = self.width - 30,
    margin = 10,
    margin_bottom = 20,
    alternate = false,

    toggle = { _("Note"), _("Quote")},
    values = { JOURNAL_NOTE, JOURNAL_QUOTE },
    config = self,
    callback = function(position)
      self.event_type = position == 1 and JOURNAL_NOTE or JOURNAL_QUOTE
    end
  }
  journal_type:setPosition(self.event_type == JOURNAL_NOTE and 1 or 2)

  local privacy_label = TextWidget:new {
    text = "Privacy: ",
    face = Font:getFace("cfont", 16)
  }

  local privacy_switch
  privacy_switch = ToggleSwitch:new{
    width = self.width - 40 - privacy_label:getWidth(),
    toggle = { _("Public"), _("Follows"), _("Private") },
    values = { 1, 2, 3 },
    alternate = false,
    config = self,
    callback = function(position)
      self.privacy_setting_id = position
    end
  }
  privacy_switch:setPosition(self.privacy_setting_id)

  local privacy_row = HorizontalGroup:new{
    privacy_label,
    HorizontalSpan:new{
      width = 10
    },
    privacy_switch
  }

  self.tag_field = InputText:new{
    width = self.width - Size.padding.default - Size.border.inputtext - 30,
    input = table.concat(self.tags, ", "),
    focused = false,
    show_parent = self,
    parent = self,
    hint = _("Tags (comma separated)"),
    face = Font:getFace("cfont", 16),
  }
  self.hidden_tag_field = InputText:new{
    width = self.width - Size.padding.default - Size.border.inputtext - 30,
    input = table.concat(self.hidden_tags, ", "),
    focused = false,
    show_parent = self,
    parent = self,
    hint = _("Hidden tags (comma separated)"),
    face = Font:getFace("cfont", 16),
  }

  self.page_button = Button:new {
    text = "page",
    text_func = function()
      return _("page " .. self.page .. " of " .. self.pages)
    end,
    width =  (self.width - 10 - 30)/2,
    text_font_size = 16,
    bordersize = Size.border.thin,
    callback = function()
      local spinner = SpinWidget:new{
        value = self.page,
        value_min = 0,
        value_max = self.pages,
        value_step = 1,
        value_hold_step = 20,
        ok_text = _("Set page"),
        title_text = _("Set current page"),
        callback = function(spin)
          self.page = spin.value
          self.page_button:setText(self.page_button.text_func(self), self.page_button.width)
        end
      }
      self:onCloseKeyboard()
      UIManager:show(spinner)
    end
  }

  self.edition_button = Button:new{
    text = "edition",
    text_func = function()
      return self.edition_format or "physical book"
    end,
    width = (self.width - 10 - 30)/2,
    text_font_size = 16,
    bordersize = Size.border.thin,
    callback = self.select_edition_callback
  }

  local edition_row = FrameContainer:new {
    padding_top = 10,
    padding_bottom = 8,
    bordersize = 0,
    HorizontalGroup:new{
      self.edition_button,
      HorizontalSpan:new{
        width = 10
      },
      self.page_button
    }
  }

  self:addWidget(journal_type)
  self:addWidget(edition_row)
  self:addWidget(privacy_row)
  self:addWidget(self.tag_field)
  self:addWidget(self.hidden_tag_field)
end

function JournalDialog:onConfigChoose(values, name, event, args, position)
  UIManager:tickAfterNext(function()
    -- TODO regional refresh
    UIManager:setDirty(self.dialog, "ui")
  end)
end

function JournalDialog:setEdition(edition_id, edition_format, edition_pages)
  self.edition_id = edition_id
  self.edition_format = edition_format
  self.pages = edition_pages or self.pages

  self.page_button:setText(self.page_button.text_func(), self.page_button.width)
  self.edition_button:setText(self.edition_button.text_func(), self.edition_button.width)
end

function JournalDialog:setModified()
  if self.input then
    self._text_modified = true
    if self.button_table then
      self.button_table:getButtonById("save"):enable()
      self:refreshButtons()
    end
  end
end

-- copied from MultiInputDialog.lua
function JournalDialog:onSwitchFocus(inputbox)
  -- unfocus current inputbox
  self._input_widget:unfocus()
  -- and close its existing keyboard (via InputDialog's thin wrapper around _input_widget's own method)
  self:onCloseKeyboard()

  UIManager:setDirty(nil, function()
    return "ui", self.dialog_frame.dimen
  end)

  -- focus new inputbox
  self._input_widget = inputbox
  self._input_widget:focus()
  self.focused_field_idx = inputbox.idx

  if (Device:hasKeyboard() or Device:hasScreenKB()) and G_reader_settings:isFalse("virtual_keyboard_enabled") then
    -- do not load virtual keyboard when user is hiding it.
    return
  end
  -- Otherwise make sure we have a (new) visible keyboard
  self:onShowKeyboard()
end

return JournalDialog
