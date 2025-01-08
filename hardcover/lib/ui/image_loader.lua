--local HTTPClient = require("httpclient")
local logger = require("logger")
local getUrlContent = require("hardcover/vendor/url_content")
local UIManager = require("ui/uimanager")
local Trapper = require("ui/trapper")

local ImageLoader = {
  url_map = {}
}

function ImageLoader:isLoading()
  return self.loading == true
end

local Batch = {
  load_count = nil,
  loading = false,
  url_map = {},
  callback = nil
}
Batch.__index = Batch

function Batch:new(o)
  return setmetatable(o or {}, self)
end

function Batch:data(url)
  return self.url_map[url]
end

function Batch:loadImages(urls)
  if self.loading then
    error("batch already in progress")
  end

  self.loading = true

  local url_queue = { table.unpack(urls) }
  local run_image
  local stop_loading = false

  run_image = function()
    Trapper:wrap(function()
      if stop_loading then return end

      local url = table.remove(url_queue, 1)

      local completed, success, content = Trapper:dismissableRunInSubprocess(function()
        return getUrlContent(url, 10, 30)
      end)

      --if not completed then
      --  logger.warn("Aborted")
      --end

      if completed and success then
        self.callback(url, content)
      end

      if #url_queue > 0 then
        UIManager:scheduleIn(0.2, run_image)
      end

      self.loading = false
    end)
  end

  if #urls == 0 then
    self.loading = false
  end

  UIManager:nextTick(run_image)

  local halt = function()
    stop_loading = true
    UIManager:unschedule(run_image)
  end

  return halt
end

function ImageLoader:loadImages(urls, callback)
  local batch = Batch:new()
  batch.callback = callback
  local halt = batch:loadImages(urls)
  return batch, halt
end

return ImageLoader
