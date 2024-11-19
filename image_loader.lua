--local HTTPClient = require("httpclient")
local logger = require("logger")
local getUrlContent = require("vendor/url_content")
local UIManager = require("ui/uimanager")

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

function Batch:new(o)
  o = o or {}   -- create object if user does not provide one
  setmetatable(o, self)
  self.__index = self
  return o
end

function Batch:data(url)
  return self.url_map[url]
end

function Batch:loadImages(urls)
  if self.loading then
    error("batch already in progress")
  end

  self.loading = true

  local url_queue = {unpack (urls)}
  local run_image
  local stop_loading = false

  run_image = function()
    if stop_loading then return end

    local url = table.remove(url_queue,1)
    local success, content = getUrlContent(url, 10, 30)

    if success then
      self.callback(url, content)
    end

    if #url_queue > 0 then
      UIManager:scheduleIn(0.2, run_image)
    end

    self.loading = false
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
  local halt = batch:loadImages(urls, callback)
  return batch, halt
end

return ImageLoader
