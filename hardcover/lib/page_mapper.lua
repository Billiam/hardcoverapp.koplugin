local _t = require("hardcover/lib/table_util")

local PageMapper = {}
PageMapper.__index = PageMapper

function PageMapper:new(o)
  return setmetatable(o or {}, self)
end

function PageMapper:getUnmappedPage(remote_page, document_pages, remote_pages)
  self:checkIgnorePagemap()

  local document_page = self.state.page_map and _t.binSearch(self.state.page_map, remote_page)

  if not document_page then
    document_page = math.floor((remote_page / remote_pages) * document_pages)
  end

  return document_page
end

function PageMapper:getMappedPage(raw_page, document_pages, remote_pages)
  self:checkIgnorePagemap()

  if self.state.page_map then
    local mapped_page = self.state.page_map[raw_page]
    if mapped_page then
      return mapped_page
    elseif raw_page > self.state.page_map_range.last_page then
      return remote_pages or self.state.page_map_range.real_page
    end
  end

  if remote_pages and document_pages then
    return math.floor((raw_page / document_pages) * remote_pages)
  end

  return raw_page
end

function PageMapper:checkIgnorePagemap()
  local current_page_labels = self.ui.pagemap:wantsPageLabels()
  if current_page_labels == self.use_page_map then
    return
  end

  self.use_page_map = current_page_labels

  if current_page_labels then
    self:cachePageMap()
  else
    self.state.page_map = nil
  end
end

local toInteger = function(number)
  local as_number = tonumber(number)
  if as_number then
    return math.floor(as_number)
  end
end

function PageMapper:cachePageMap()
  if not self.ui.pagemap:wantsPageLabels() then
    return
  end
  local page_map = self.ui.document:getPageMap()

  local lookup = {}
  local page_label = 1
  local last_page_label = 1
  local last_page = 1
  local max_page_label = 1

  for _, v in ipairs(page_map) do
    page_label = toInteger(v.label) or page_label

    for i = last_page, v.page, 1 do
      lookup[i] = last_page_label
    end

    lookup[v.page] = page_label
    last_page = v.page
    max_page_label = page_label > max_page_label and page_label or max_page_label
    last_page_label = page_label
  end

  self.state.page_map_range = {
    real_page = max_page_label,
    last_page = last_page,
  }
  self.state.page_map = lookup
end

function PageMapper:getMappedPagePercent(raw_page, document_pages, remote_pages)
  local mapped_page = self.state.page_map and self.state.page_map[raw_page]

  if mapped_page and remote_pages then
    return mapped_page / remote_pages
  end

  if document_pages then
    return raw_page / document_pages
  end

  return 0
end

function PageMapper:getRemotePagePercent(raw_page, document_pages, remote_pages)
  local total_pages = remote_pages or document_pages
  local local_percent = self:getMappedPagePercent(raw_page, document_pages, remote_pages)

  local remote_page = math.floor(local_percent * total_pages)
  return remote_page / total_pages, remote_page
end

return PageMapper
