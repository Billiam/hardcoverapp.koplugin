local _ = require("gettext")
local socket = require("socket")

local T = require("ffi/util").template

local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")

local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")

local Api = require("hardcover/lib/hardcover_api")
local JournalEntry = require("hardcover/lib/journal_entry")

-- book setting key holding a map of annotation datetime -> journal entry id
local EXPORTED_SETTING = "journal_exported"
-- pause between requests to stay under the Hardcover API rate limit (60/minute)
local REQUEST_DELAY = 1

local JournalExporter = {}
JournalExporter.__index = JournalExporter

function JournalExporter:new(o)
  return setmetatable(o or {}, self)
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

function JournalExporter:export()
  if not self.ui.document or not self.settings:bookLinked() then
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
    text = T(_("Export %1 highlights and notes to your Hardcover journal?"), #pending),
    ok_text = _("Export"),
    ok_callback = function()
      self.wifi:withWifi(function()
        Trapper:wrap(function()
          self:_runExport(file, pending)
        end)
      end)
    end
  })
end

function JournalExporter:_runExport(file, pending)
  local book_settings = self.settings:readBookSettings(file) or {}
  local remote_pages = self.settings:pages()
  local document_pages = self.ui.document:getPageCount()
  local exported = self.settings:readBookSetting(file, EXPORTED_SETTING) or {}

  local sent = 0
  local aborted = false
  local failed = false

  for i, annotation in ipairs(pending) do
    local go_on = Trapper:info(T(_("Exporting %1 of %2…"), i, #pending))
    if not go_on then
      aborted = true
      break
    end

    local mapped_page
    if annotation.pageno then
      mapped_page = self.page_mapper:getMappedPage(annotation.pageno, document_pages, remote_pages)
    end

    local entry = JournalEntry.build(annotation, {
      book_id = book_settings.book_id,
      edition_id = book_settings.edition_id,
      privacy_setting_id = self.state.book_status.privacy_setting_id,
      page = mapped_page,
      pages = remote_pages
    })

    if entry then
      local result = Api:createJournalEntry(entry)
      if not result then
        socket.sleep(REQUEST_DELAY)
        result = Api:createJournalEntry(entry)
      end

      if result then
        sent = sent + 1
        exported[JournalEntry.annotationKey(annotation)] = result.id or true
        self.settings:updateBookSetting(file, { [EXPORTED_SETTING] = exported })
      else
        failed = true
        break
      end

      if i < #pending then
        socket.sleep(REQUEST_DELAY)
      end
    end
  end

  Trapper:clear()

  local message
  if failed then
    message = T(_("Export stopped: %1 of %2 entries saved. Retrying later will skip already exported entries."), sent,
      #pending)
  elseif aborted then
    message = T(_("Export canceled: %1 of %2 entries saved"), sent, #pending)
  else
    message = T(_("Exported %1 journal entries"), sent)
  end

  UIManager:show(InfoMessage:new {
    text = message,
    icon = failed and "notice-warning" or nil,
    timeout = failed and nil or 3
  })
end

return JournalExporter
