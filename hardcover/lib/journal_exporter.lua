local _ = require("gettext")
local logger = require("logger")

local T = require("ffi/util").template

local UIManager = require("ui/uimanager")

local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")

local Api = require("hardcover/lib/hardcover_api")
local JournalEntry = require("hardcover/lib/journal_entry")

-- book setting key holding a map of annotation datetime -> journal entry id
local EXPORTED_SETTING = "journal_exported"
-- pause between requests to stay under the Hardcover API rate limit (60/minute)
local REQUEST_DELAY = 1

local JournalExporter = {}
JournalExporter.__index = JournalExporter

function JournalExporter:new(o)
  o = o or {}
  o.running = false
  return setmetatable(o, self)
end

function JournalExporter:_annotations()
  return self.ui.annotation and self.ui.annotation.annotations or {}
end

function JournalExporter:_exported()
  local file = self.ui.document and self.ui.document.file
  if not file then
    return {}
  end

  return self.settings:readBookSetting(file, EXPORTED_SETTING) or {}
end

function JournalExporter:pendingCount()
  return #JournalEntry.pending(self:_annotations(), self:_exported())
end

function JournalExporter:clearHistory()
  local file = self.ui.document and self.ui.document.file
  if file then
    self.settings:updateBookSetting(file, { _delete = { EXPORTED_SETTING } })
  end
end

-- Stop a running export after the in-flight request completes.
-- Already exported entries are remembered, so a later export resumes
-- where this one stopped.
function JournalExporter:cancel()
  self.stop_requested = true
end

-- Silent export cycle for scheduled/background use: no dialogs, no
-- notifications, nothing to tap. Skipped entirely when wifi is off and
-- cannot be enabled without user interaction.
function JournalExporter:exportSilently()
  if self.running or not Api.enabled or not self.ui.document or not self.settings:bookLinked() then
    return
  end

  local file = self.ui.document.file
  local pending = JournalEntry.pending(self:_annotations(), self:_exported())
  if #pending == 0 then
    return
  end

  self.wifi:holdWifi(function(release_wifi)
    self:_startQueue(file, pending, release_wifi)
  end)
end

-- Manual export from the menu: confirmation up front, notification when done
function JournalExporter:export()
  if not self.ui.document or not self.settings:bookLinked() then
    return
  end

  if self.running then
    UIManager:show(Notification:new {
      text = _("Journal export already running"),
    })
    return
  end

  local file = self.ui.document.file
  local pending = JournalEntry.pending(self:_annotations(), self:_exported())

  if #pending == 0 then
    UIManager:show(InfoMessage:new {
      text = _("No new highlights or notes to export"),
      timeout = 2
    })
    return
  end

  UIManager:show(ConfirmBox:new {
    text = T(_("Export %1 highlights and notes to your Hardcover journal?\n\nThe export runs in the background; you can keep reading."), #pending),
    ok_text = _("Export"),
    ok_callback = function()
      self.wifi:wifiPrompt(function()
        local pending_now = JournalEntry.pending(self:_annotations(), self:_exported())
        if #pending_now > 0 then
          self:_startQueue(file, pending_now, function() end, true)
        end
      end)
    end
  })
end

function JournalExporter:_startQueue(file, pending, release_wifi, notify)
  local book_settings = self.settings:readBookSettings(file) or {}
  local remote_pages = self.settings:pages()
  local document_pages = self.ui.document:getPageCount()
  local exported = self.settings:readBookSetting(file, EXPORTED_SETTING) or {}

  self.running = true
  self.stop_requested = false

  local index = 0
  local sent = 0

  local finish = function(failed)
    self.running = false
    release_wifi()

    logger.info("hardcover: journal export finished;", sent, "of", #pending, "entries sent",
      failed and "(stopped on error)" or "")

    if notify then
      local message
      if failed then
        message = T(_("Hardcover export stopped: %1 of %2 entries saved"), sent, #pending)
      else
        message = T(_("Hardcover: exported %1 journal entries"), sent)
      end
      UIManager:show(Notification:new {
        text = message,
      })
    end
  end

  local step
  step = function()
    index = index + 1

    -- stop when cancelled, or when the document changed under us
    if self.stop_requested or not self.ui.document or self.ui.document.file ~= file then
      return finish()
    end

    if index > #pending then
      return finish()
    end

    local annotation = pending[index]
    local entry = JournalEntry.build(annotation, {
      book_id = book_settings.book_id,
      edition_id = book_settings.edition_id,
      privacy_setting_id = self.state.book_status.privacy_setting_id,
      page = annotation.pageno and self.page_mapper:getMappedPage(annotation.pageno, document_pages, remote_pages),
      pages = remote_pages
    })

    if not entry then
      return UIManager:nextTick(step)
    end

    Api:createJournalEntryAsync(entry, function(result)
      if result then
        sent = sent + 1
        exported[JournalEntry.annotationKey(annotation)] = result.id or true
        self.settings:updateBookSetting(file, { [EXPORTED_SETTING] = exported })
        UIManager:scheduleIn(REQUEST_DELAY, step)
      else
        -- leave the remaining entries for the next run
        finish(true)
      end
    end)
  end

  step()
end

return JournalExporter
