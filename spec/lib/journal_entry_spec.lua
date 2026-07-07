package.preload["json"] = package.preload["json"] or function()
  return {
    util = {
      InitArray = function(t)
        return t
      end
    }
  }
end

local JournalEntry = require("hardcover/lib/journal_entry")

local NIL = "__nil__"

local function highlight(overrides)
  local annotation = {
    drawer = "lighten",
    text = "The quick brown fox",
    datetime = "2026-07-01 21:15:00",
    pageno = 12
  }
  for k, v in pairs(overrides or {}) do
    annotation[k] = v ~= NIL and v or nil
  end
  return annotation
end

describe("JournalEntry", function()
  describe("build", function()
    it("builds a quote entry from a highlight", function()
      local entry = JournalEntry.build(highlight(), { book_id = 100, edition_id = 200, privacy_setting_id = 3 })

      assert.same({
        book_id = 100,
        edition_id = 200,
        event = "quote",
        entry = "The quick brown fox",
        privacy_setting_id = 3,
        action_at = "2026-07-01",
        tags = {}
      }, entry)
    end)

    it("builds a note entry when the annotation has a note", function()
      local entry = JournalEntry.build(highlight({ note = "so fast" }), { book_id = 100 })

      assert.equal("note", entry.event)
      assert.equal("> The quick brown fox\n\nso fast", entry.entry)
    end)

    it("defaults privacy to public", function()
      local entry = JournalEntry.build(highlight(), { book_id = 100 })

      assert.equal(1, entry.privacy_setting_id)
    end)

    it("omits action_at when datetime is missing", function()
      local entry = JournalEntry.build(highlight({ datetime = NIL }), { book_id = 100 })

      assert.is_nil(entry.action_at)
    end)

    it("omits action_at when datetime is malformed", function()
      local entry = JournalEntry.build(highlight({ datetime = "yesterday" }), { book_id = 100 })

      assert.is_nil(entry.action_at)
    end)

    it("includes page position metadata when a page is given", function()
      local entry = JournalEntry.build(highlight(), { book_id = 100, page = 42, pages = 300 })

      assert.same({
        position = {
          type = "pages",
          value = 42,
          possible = 300
        }
      }, entry.metadata)
    end)

    it("returns nil for page bookmarks", function()
      assert.is_nil(JournalEntry.build(highlight({ drawer = NIL }), { book_id = 100 }))
    end)

    it("returns nil for empty highlights", function()
      assert.is_nil(JournalEntry.build(highlight({ text = "" }), { book_id = 100 }))
      assert.is_nil(JournalEntry.build(highlight({ text = NIL }), { book_id = 100 }))
    end)
  end)

  describe("pending", function()
    it("filters out already exported annotations by datetime", function()
      local first = highlight()
      local second = highlight({ datetime = "2026-07-02 08:00:00" })
      local exported = { ["2026-07-01 21:15:00"] = 123 }

      local result = JournalEntry.pending({ first, second }, exported)

      assert.same({ second }, result)
    end)

    it("filters out page bookmarks and empty highlights", function()
      local bookmark = highlight({ drawer = NIL })
      local empty = highlight({ text = "" })
      local valid = highlight()

      local result = JournalEntry.pending({ bookmark, empty, valid }, {})

      assert.same({ valid }, result)
    end)

    it("handles nil annotation and exported lists", function()
      assert.same({}, JournalEntry.pending(nil, nil))
      assert.same({ highlight() }, JournalEntry.pending({ highlight() }, nil))
    end)

    it("falls back to annotation text as the exported key", function()
      local no_datetime = highlight({ datetime = NIL })

      local result = JournalEntry.pending({ no_datetime }, { ["The quick brown fox"] = true })

      assert.same({}, result)
    end)
  end)
end)
