-- Test driver: waits for the reader and the hardcover plugin, injects
-- annotations, runs the silent background export twice (second run must be a
-- dedup no-op), then exits with a status code the harness can check.
local logger = require("logger")
local UIManager = require("ui/uimanager")

logger.info("JOURNAL-EXPORT-TEST: patch loaded")

local annotations = {
  {
    datetime = "2026-07-01 10:00:00",
    drawer = "lighten",
    text = "First highlighted passage",
    chapter = "Chapter One",
    pageno = 3,
  },
  {
    datetime = "2026-07-02 11:30:00",
    drawer = "lighten",
    text = "Second highlighted passage",
    note = "my thought about this",
    pageno = 5,
  },
  {
    datetime = "2026-07-03 12:45:00",
    drawer = "lighten",
    text = "Third highlighted passage",
    pageno = 7,
  },
  {
    -- page bookmark: must be skipped
    datetime = "2026-07-03 13:00:00",
    text = "Page 8 bookmark",
    pageno = 8,
  },
}

local function fail(message, code)
  logger.warn("JOURNAL-EXPORT-TEST: FAIL:", message)
  os.exit(code or 1)
end

local attempts = 0
local function run()
  attempts = attempts + 1

  local ok, ReaderUI = pcall(require, "apps/reader/readerui")
  local ui = ok and ReaderUI.instance
  local plugin = ui and (ui.hardcoverappsync or ui.hardcoverapp)

  if not plugin then
    if attempts < 30 then
      UIManager:scheduleIn(1, run)
      return
    end
    fail("hardcover plugin not found in reader", 11)
  end

  logger.info("JOURNAL-EXPORT-TEST: plugin found, injecting annotations")
  ui.annotation.annotations = annotations

  local exporter = plugin.journal_exporter
  if exporter:pendingCount() ~= 3 then
    fail("expected 3 pending annotations, got " .. exporter:pendingCount(), 12)
  end

  logger.info("JOURNAL-EXPORT-TEST: starting silent export")
  local started = os.time()
  exporter:exportSilently()

  local waited = 0
  local function waitForFinish()
    waited = waited + 1
    if exporter.running then
      if waited > 90 then
        fail("export did not finish in time", 13)
      end
      UIManager:scheduleIn(1, waitForFinish)
      return
    end

    local elapsed = os.time() - started
    local pending = exporter:pendingCount()
    logger.info("JOURNAL-EXPORT-TEST: export finished in", elapsed, "seconds, pending now", pending)

    if pending ~= 0 then
      fail("expected 0 pending after export, got " .. pending, 14)
    end

    -- second run must be a no-op: nothing pending, queue must not start
    exporter:exportSilently()
    if exporter.running then
      fail("second export started a queue despite nothing pending", 15)
    end

    logger.info("JOURNAL-EXPORT-TEST: PASS")
    os.exit(0)
  end

  UIManager:scheduleIn(2, waitForFinish)
end

UIManager:scheduleIn(5, run)
