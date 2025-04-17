local DataStorage = require("datastorage")
local Device = require("device")
local _ = require("gettext")
local math = require("math")
local os = require("os")
local logger = require("logger")

local T = require("ffi/util").template

local Font = require("ui/font")
local UIManager = require("ui/uimanager")

local UpdateDoubleSpinWidget = require("hardcover/lib/ui/update_double_spin_widget")
local InfoMessage = require("ui/widget/infomessage")
local SpinWidget = require("ui/widget/spinwidget")

local Api = require("hardcover/lib/hardcover_api")
local Github = require("hardcover/lib/github")
local User = require("hardcover/lib/user")
local _t = require("hardcover/lib/table_util")

local HARDCOVER = require("hardcover/lib/constants/hardcover")
local ICON = require("hardcover/lib/constants/icons")
local SETTING = require("hardcover/lib/constants/settings")
local VERSION = require("hardcover_version")

local HardcoverMenu = {}
HardcoverMenu.__index = HardcoverMenu

function HardcoverMenu:new(o)
  return setmetatable(o or {
    enabled = true
  }, self)
end

local privacy_labels = {
  [HARDCOVER.PRIVACY.PUBLIC] = "Public",
  [HARDCOVER.PRIVACY.FOLLOWS] = "Follows",
  [HARDCOVER.PRIVACY.PRIVATE] = "Private"
}

function HardcoverMenu:mainMenu()
  return {
    enabled_func = function()
      return self.enabled
    end,
    text_func = function()
      return self.settings:bookLinked() and _("Hardcover: " .. ICON.LINK) or _("Hardcover")
    end,
    sub_item_table_func = function()
      local has_book = self.ui.document and true or false
      return self:getSubMenuItems(has_book)
    end,
  }
end

function HardcoverMenu:getSubMenuItems(book_view)
  local menu_items = {
    book_view and {
      text_func = function()
        if self.settings:bookLinked() then
          -- need to show link information somehow. Maybe store title
          local title = self.settings:getLinkedTitle()
          if not title then
            title = self.settings:getLinkedBookId()
          end
          return _("Linked book: " .. title)
        else
          return _("Link book")
        end
      end,
      enabled_func = function()
        -- leave button enabled to allow clearing local link when api disabled
        return self.enabled or self.settings:bookLinked()
      end,
      hold_callback = function(menu_instance)
        if self.settings:bookLinked() then
          self.settings:updateBookSetting(
            self.ui.document.file,
            {
              _delete = { 'book_id', 'edition_id', 'edition_format', 'pages', 'title' }
            }
          )

          menu_instance:updateItems()
        end
      end,
      keep_menu_open = true,
      callback = function(menu_instance)
        if not self.enabled then
          return
        end

        local force_search = self.settings:bookLinked()

        self.hardcover:showLinkBookDialog(force_search, function()
          menu_instance:updateItems()
        end)
      end,
    },
    book_view and {
      text_func = function()
        local edition_format = self.settings:getLinkedEditionFormat()
        local title = "Change edition"

        if edition_format then
          title = title .. ": " .. edition_format
        elseif self.settings:getLinkedEditionId() then
          return title .. ": physical book"
        end

        return _(title)
      end,
      enabled_func = function()
        return self.enabled and self.settings:bookLinked()
      end,
      callback = function(menu_instance)
        local editions = Api:findEditions(self.settings:getLinkedBookId(), User:getId())
        -- need to show "active" here, and prioritize current edition if available
        self.dialog_manager:buildSearchDialog(
          "Select edition",
          editions,
          {
            edition_id = self.settings:getLinkedEditionId()
          },
          function(book)
            self.hardcover:linkBook(book)
            menu_instance:updateItems()
          end
        )
      end,
      keep_menu_open = true,
      separator = true
    },
    book_view and {
      text = _("Automatically track progress"),
      checked_func = function()
        return self.settings:syncEnabled()
      end,
      enabled_func = function()
        return self.settings:bookLinked()
      end,
      callback = function()
        local sync = not self.settings:syncEnabled()
        self.settings:setSync(sync)
      end,
    },
    book_view and {
      text = _("Update status"),
      enabled_func = function()
        return self.settings:bookLinked()
      end,
      sub_item_table_func = function()
        self.cache:cacheUserBook()

        return self:getStatusSubMenuItems()
      end,
      separator = true
    },
    {
      text = _("Suggest a book"),
      callback = function()
        self.hardcover:showRandomBookDialog()
      end,
      separator = true,
      keep_menu_open = true
    },
    {
      text = _("Settings"),
      sub_item_table_func = function()
        return self:getSettingsSubMenuItems()
      end,
    },
    {
      text = _("About"),
      callback = function()
        local new_release = Github:newestRelease()
        local version = table.concat(VERSION, ".")
        local new_release_str = ""
        if new_release then
          new_release_str = " (latest v" .. new_release .. ")"
        end
        local settings_file = DataStorage:getSettingsDir() .. "/" .. "hardcoversync_settings.lua"

        UIManager:show(InfoMessage:new {
          text = [[
Hardcover plugin
v]] .. version .. new_release_str .. [[


Updates book progress and status on Hardcover.app

Project:
github.com/billiam/hardcoverapp.koplugin

Settings:
]] .. settings_file,
          face = Font:getFace("cfont", 18),
          show_icon = false,
        })
      end,
      keep_menu_open = true
    }
  }
  return _t.filter(menu_items, function(v) return v end)
end

function HardcoverMenu:getVisibilitySubMenuItems()
  return {
    {
      text = _(privacy_labels[HARDCOVER.PRIVACY.PUBLIC]),
      checked_func = function()
        return self.state.book_status.privacy_setting_id == HARDCOVER.PRIVACY.PUBLIC
      end,
      callback = function()
        self.hardcover:changeBookVisibility(HARDCOVER.PRIVACY.PUBLIC)
      end,
      radio = true,
    },
    {
      text = _(privacy_labels[HARDCOVER.PRIVACY.FOLLOWS]),
      checked_func = function()
        return self.state.book_status.privacy_setting_id == HARDCOVER.PRIVACY.FOLLOWS
      end,
      callback = function()
        self.hardcover:changeBookVisibility(HARDCOVER.PRIVACY.FOLLOWS)
      end,
      radio = true
    },
    {
      text = _(privacy_labels[HARDCOVER.PRIVACY.PRIVATE]),
      checked_func = function()
        return self.state.book_status.privacy_setting_id == HARDCOVER.PRIVACY.PRIVATE
      end,
      callback = function()
        self.hardcover:changeBookVisibility(HARDCOVER.PRIVACY.PRIVATE)
      end,
      radio = true
    },
  }
end

function HardcoverMenu:getStatusSubMenuItems()
  return {
    {
      text = _(ICON.BOOKMARK .. " Want To Read"),
      enabled_func = function()
        return self.enabled
      end,
      checked_func = function()
        return self.state.book_status.status_id == HARDCOVER.STATUS.TO_READ
      end,
      callback = function()
        self.cache:updateBookStatus(self.ui.document.file, HARDCOVER.STATUS.TO_READ)
      end,
      radio = true
    },
    {
      text = _(ICON.OPEN_BOOK .. " Currently Reading"),
      enabled_func = function()
        return self.enabled
      end,
      checked_func = function()
        return self.state.book_status.status_id == HARDCOVER.STATUS.READING
      end,
      callback = function()
        self.cache:updateBookStatus(self.ui.document.file, HARDCOVER.STATUS.READING)
      end,
      radio = true
    },
    {
      text = _(ICON.CHECKMARK .. " Read"),
      enabled_func = function()
        return self.enabled
      end,
      checked_func = function()
        return self.state.book_status.status_id == HARDCOVER.STATUS.FINISHED
      end,
      callback = function()
        self.cache:updateBookStatus(self.ui.document.file, HARDCOVER.STATUS.FINISHED)
      end,
      radio = true
    },
    {
      text = _(ICON.STOP_CIRCLE .. " Did Not Finish"),
      enabled_func = function()
        return self.enabled
      end,
      checked_func = function()
        return self.state.book_status.status_id == HARDCOVER.STATUS.DNF
      end,
      callback = function()
        self.cache:updateBookStatus(self.ui.document.file, HARDCOVER.STATUS.DNF)
      end,
      radio = true,
    },
    {
      text = _(ICON.TRASH .. " Remove"),
      enabled_func = function()
        return self.enabled and self.state.book_status.status_id ~= nil
      end,
      callback = function(menu_instance)
        local result = Api:removeRead(self.state.book_status.id)
        if result and result.id then
          self.state.book_status = {}
          menu_instance:updateItems()
        end
      end,
      keep_menu_open = true,
      separator = true
    },
    {
      text_func = function()
        local reads = self.state.book_status.user_book_reads
        local current_page = reads and reads[#reads] and reads[#reads].progress_pages or 0
        local max_pages = self.settings:pages()

        if not max_pages then
          max_pages = "???"
        end

        return T(_("Update page: %1 of %2"), current_page, max_pages)
      end,
      enabled_func = function()
        return self.enabled and self.state.book_status.status_id == HARDCOVER.STATUS.READING and self.settings:pages()
      end,
      callback = function(menu_instance)
        local reads = self.state.book_status.user_book_reads
        local current_read = reads and reads[#reads]
        local last_hardcover_page = current_read and current_read.progress_pages or 0

        local document_page = self.ui:getCurrentPage()
        local document_pages = self.ui.document:getPageCount()

        local remote_pages = self.settings:pages()
        local mapped_page = self.page_mapper:getMappedPage(document_page, document_pages, remote_pages)

        local left_text = "Edition"
        if last_hardcover_page > 0 then
          left_text = left_text .. ": was " .. last_hardcover_page
        end

        local spinner = UpdateDoubleSpinWidget:new {
          ok_always_enabled = true,

          left_text = left_text,
          left_value = mapped_page,
          left_min = 0,
          left_max = remote_pages,
          left_step = 1,
          left_hold_step = 20,

          right_text = "Local page",
          right_value = document_page,
          right_min = 0,
          right_max = document_pages,
          right_step = 1,
          right_hold_step = 20,

          update_callback = function(new_edition_page, new_document_page, edition_page_changed)
            if edition_page_changed then
              local new_mapped_page = self.page_mapper:getUnmappedPage(new_edition_page, document_pages, remote_pages)
              return new_edition_page, new_mapped_page
            else
              local new_mapped_page = self.page_mapper:getMappedPage(new_document_page, document_pages, remote_pages)
              return new_mapped_page, new_document_page
            end
          end,
          ok_text = _("Set page"),
          title_text = _("Set current page"),

          callback = function(edition_page, _document_page)
            local result

            if current_read then
              result = Api:updatePage(current_read.id, current_read.edition_id, edition_page,
                current_read.started_at)
            else
              local start_date = os.date("%Y-%m-%d")
              result = Api:createRead(self.state.book_status.id, self.state.book_status.edition_id, edition_page,
                start_date)
            end

            if result then
              self.state.book_status = result
              menu_instance:updateItems()
            else

            end
          end
        }
        UIManager:show(spinner)
      end,
      keep_menu_open = true
    },
    {
      text = _("Add a note"),
      enabled_func = function()
        return self.enabled and self.state.book_status.id ~= nil
      end,
      callback = function()
        local reads = self.state.book_status.user_book_reads
        local current_read = reads and reads[#reads]
        local current_page = current_read and current_read.progress_pages or 0

        -- allow premapped page
        self.dialog_manager:journalEntryForm(
          "",
          self.ui.document,
          current_page,
          self.settings:pages(),
          current_page,
          "note"
        )
      end,
      keep_menu_open = true
    },
    {
      text_func = function()
        local text
        if self.state.book_status.rating then
          text = "Update rating"
          local whole_star = math.floor(self.state.book_status.rating)
          local star_string = string.rep(ICON.STAR, whole_star)
          if self.state.book_status.rating - whole_star > 0 then
            star_string = star_string .. ICON.HALF_STAR
          end
          text = text .. ": " .. star_string
        else
          text = "Set rating"
        end

        return _(text)
      end,
      enabled_func = function()
        return self.enabled and self.state.book_status.id ~= nil
      end,
      callback = function(menu_instance)
        local rating = self.state.book_status.rating

        local spinner = SpinWidget:new {
          ok_always_enabled = rating == nil,
          value = rating or 2.5,
          value_min = 0,
          value_max = 5,
          value_step = 0.5,
          value_hold_step = 2,
          precision = "%.1f",
          ok_text = _("Save"),
          title_text = _("Set Rating"),
          callback = function(spin)
            local result = Api:updateRating(self.state.book_status.id, spin.value)
            if result then
              self.state.book_status = result
              menu_instance:updateItems()
            else
              self.dialog_magager:showError("Rating could not be saved")
            end
          end
        }
        UIManager:show(spinner)
      end,
      hold_callback = function(menu_instance)
        local result = Api:updateRating(self.state.book_status.id, 0)
        if result then
          self.state.book_status = result
          menu_instance:updateItems()
        end
      end,
      keep_menu_open = true,
      separator = true
    },
    {
      text = _("Set status visibility"),
      enabled_func = function()
        return self.enabled and self.state.book_status.id ~= nil
      end,
      sub_item_table_func = function()
        return self:getVisibilitySubMenuItems()
      end,
    },
  }
end

function HardcoverMenu:getTrackingSubMenuItems()
  return {
    {
      text = "Update periodically",
      radio = true,
      checked_func = function()
        return self.settings:trackByTime()
      end,
      callback = function()
        self.settings:setTrackMethod(SETTING.TRACK.FREQUENCY)
      end
    },
    {
      text_func = function()
        return "Every " .. self.settings:trackFrequency() .. " minutes"
      end,
      enabled_func = function()
        return self.settings:trackByTime()
      end,
      callback = function(menu_instance)
        local spinner = SpinWidget:new {
          value = self.settings:trackFrequency(),
          value_min = 1,
          value_max = 120,
          value_step = 1,
          value_hold_step = 6,
          ok_text = _("Save"),
          title_text = _("Set track frequency"),
          callback = function(spin)
            self.settings:updateSetting(SETTING.TRACK_FREQUENCY, spin.value)
            menu_instance:updateItems()
          end
        }

        UIManager:show(spinner)
      end,
      keep_menu_open = true
    },
    {
      text = "Update by progress",
      radio = true,
      checked_func = function()
        return self.settings:trackByProgress()
      end,
      callback = function()
        self.settings:setTrackMethod(SETTING.TRACK.PROGRESS)
      end
    },
    {
      text_func = function()
        return "Every " .. self.settings:trackPercentageInterval() .. " percent completed"
      end,
      enabled_func = function()
        return self.settings:trackByProgress()
      end,
      callback = function(menu_instance)
        local spinner = SpinWidget:new {
          value = self.settings:trackPercentageInterval(),
          value_min = 1,
          value_max = 50,
          value_step = 1,
          value_hold_step = 10,
          ok_text = _("Save"),
          title_text = _("Set track progress"),
          callback = function(spin)
            self.settings:changeTrackPercentageInterval(spin.value)
            menu_instance:updateItems()
          end
        }

        UIManager:show(spinner)
      end,
      keep_menu_open = true
    },
  }
end

function HardcoverMenu:getSettingsSubMenuItems()
  return {
    {
      text = "Automatically link by ISBN",
      checked_func = function()
        return self.settings:readSetting(SETTING.LINK_BY_ISBN) == true
      end,
      callback = function()
        local setting = self.settings:readSetting(SETTING.LINK_BY_ISBN) == true
        self.settings:updateSetting(SETTING.LINK_BY_ISBN, not setting)
      end
    },
    {
      text = "Automatically link by Hardcover identifiers",
      checked_func = function()
        return self.settings:readSetting(SETTING.LINK_BY_HARDCOVER) == true
      end,
      callback = function()
        local setting = self.settings:readSetting(SETTING.LINK_BY_HARDCOVER) == true
        self.settings:updateSetting(SETTING.LINK_BY_HARDCOVER, not setting)
      end
    },
    {
      text = "Automatically link by title and author",
      checked_func = function()
        return self.settings:readSetting(SETTING.LINK_BY_TITLE) == true
      end,
      callback = function()
        local setting = self.settings:readSetting(SETTING.LINK_BY_TITLE) == true
        self.settings:updateSetting(SETTING.LINK_BY_TITLE, not setting)
      end,
      separator = true
    },
    {
      text_func = function()
        return "Track progress settings: " .. ""
      end,
      sub_item_table_func = function()
        return self:getTrackingSubMenuItems()
      end,
    },
    {
      text = "Always track progress by default",
      checked_func = function()
        return self.settings:readSetting(SETTING.ALWAYS_SYNC) == true
      end,
      callback = function()
        local setting = self.settings:readSetting(SETTING.ALWAYS_SYNC) == true
        self.settings:updateSetting(SETTING.ALWAYS_SYNC, not setting)
      end,
    },
    {
      text = "Enable wifi on demand",
      checked_func = function()
        return self.settings:readSetting(SETTING.ENABLE_WIFI) == true
      end,
      enabled_func = function()
        return Device:hasWifiRestore()
      end,
      callback = function()
        local setting = self.settings:readSetting(SETTING.ENABLE_WIFI) == true
        self.settings:updateSetting(SETTING.ENABLE_WIFI, not setting)
      end
    },
    {
      text = "Compatibility mode",
      checked_func = function()
        return self.settings:compatibilityMode()
      end,
      callback = function()
        local setting = self.settings:compatibilityMode()
        self.settings:updateSetting(SETTING.COMPATIBILITY_MODE, not setting)
      end,
      hold_callback = function()
        UIManager:show(InfoMessage:new {
          text = [[Disable fancy menu for book and edition search results.

May improve compatibility for some versions of KOReader]],
        })
      end
    }
  }
end

return HardcoverMenu
