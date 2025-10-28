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
    elseif raw_page > #self.state.page_map then
      return remote_pages
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

function PageMapper:cachePageMap()
  if not self.ui.pagemap:wantsPageLabels() then
    return
  end

  local page_map = self.ui.document:getPageMap()
  if not page_map then
    return
  end

  local lookup = {}
  local last_label
  local real_page = 1
  local last_page = 1

  for _, v in ipairs(page_map) do
    for i = last_page, v.page, 1 do
      lookup[i] = real_page
    end

    if last_label ~= nil and v.label ~= last_label then
      real_page = real_page + 1
    end

    last_label = v.label

    lookup[v.page] = real_page
    last_page = v.page
  end

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
