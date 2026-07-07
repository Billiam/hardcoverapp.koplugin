local json = require("json")

local HARDCOVER = require("hardcover/lib/constants/hardcover")

local JournalEntry = {}

function JournalEntry.annotationKey(annotation)
  return annotation.datetime or annotation.text
end

function JournalEntry.exportable(annotation)
  return annotation.drawer ~= nil and annotation.text ~= nil and annotation.text ~= ""
end

-- Convert a KOReader annotation to a ReadingJournalCreateType object.
-- Highlights become quote entries, highlights with a note become note
-- entries containing both the quoted text and the note. Page bookmarks
-- and empty highlights return nil.
function JournalEntry.build(annotation, opts)
  if not JournalEntry.exportable(annotation) then
    return
  end

  local event, entry
  if annotation.note and annotation.note ~= "" then
    event = "note"
    entry = "> " .. annotation.text .. "\n\n" .. annotation.note
  else
    event = "quote"
    entry = annotation.text
  end

  local result = {
    book_id = opts.book_id,
    edition_id = opts.edition_id,
    event = event,
    entry = entry,
    privacy_setting_id = opts.privacy_setting_id or HARDCOVER.PRIVACY.PUBLIC,
    tags = json.util.InitArray({})
  }

  local action_at = annotation.datetime and annotation.datetime:match("^%d%d%d%d%-%d%d%-%d%d")
  if action_at then
    result.action_at = action_at
  end

  if opts.page then
    result.metadata = {
      position = {
        type = "pages",
        value = opts.page,
        possible = opts.pages
      }
    }
  end

  return result
end

-- Filter out annotations which cannot be exported (page bookmarks,
-- empty highlights) or which have already been exported
function JournalEntry.pending(annotations, exported)
  local result = {}
  for _, annotation in ipairs(annotations or {}) do
    if JournalEntry.exportable(annotation) and not (exported and exported[JournalEntry.annotationKey(annotation)]) then
      table.insert(result, annotation)
    end
  end
  return result
end

return JournalEntry
