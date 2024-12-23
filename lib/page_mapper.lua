local PageMapper = {}

function PageMapper:init(o)
  setmetatable(o, self)
  o.__index = self

  return o
end

function PageMapper:getMappedPage(raw_page, document_pages, remote_pages)
  local mapped_page = self.state.page_map and self.state.page_map[raw_page]

  if mapped_page then
    return mapped_page
  end

  if remote_pages and document_pages then
    return math.floor((raw_page / document_pages) * remote_pages + 0.5)
  end

  return raw_page
end

function PageMapper:cachePageMap()
  if not self.ui.document.getPageMap then
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

    if v.label ~= last_label then
      real_page = real_page + 1
      last_label = v.label
    end
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

return PageMapper
