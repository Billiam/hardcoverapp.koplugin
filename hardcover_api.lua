local config = require("config")
local logger = require("logger")
local https = require("ssl.https")
local ltn12 = require("ltn12")
local json = require("json")

local api_url = "https://api.hardcover.app/v1/graphql"
local headers = {
  ["Content-Type"] = "application/json",
  Authorization = "Bearer " .. config.token
}

local HardcoverApi = {
}

local book_fragment = [[
fragment BookParts on books {
  id
  title
  release_year
  users_read_count
  pages
  book_series {
    position
    series {
      name
    }
  }
  contributions {
    author {
      name
      alternate_names
    }
  }
  cached_image
  user_books(where: { user_id: { _eq: $userId }}) {
    id
  }
}]]

local edition_fragment = book_fragment .. [[
fragment EditionParts on editions {
  id
  book {
    ...BookParts
  }
  cached_image
  edition_format
  pages
  publisher {
    name
  }
  release_date
  users_count
}]]

local user_book_fragment = [[
fragment UserBookParts on user_books {
  id
  status_id
  privacy_setting_id
}]]

-- TODO: Remove when search API ready
function escapeLike(str)
  return str:gsub("%%", "\\%%"):gsub("_", "\\_")
end

function HardcoverApi:query(query, parameters)
  local requestBody = {
    query = query,
    variables = parameters
  }
  local responseBody = {}

  local res, code, responseHeaders = https.request {
    url = api_url,
    method = "POST",
    headers = headers,
    source = ltn12.source.string(json.encode(requestBody)),
    sink = ltn12.sink.table(responseBody),
  }
  --logger.warn(requestBody)
  --logger.warn(responseBody)
  if code == 200 then
    local data = json.decode(table.concat(responseBody), json.decode.simple)
    if data.data then
      return data.data
    elseif data.errors then
      logger.err("Query error", data.errors)
      logger.err("Query", requestBody)
    end
  else
    logger.err("Error code", code, responseBody)
  end
end

function HardcoverApi:hydrateBooks(ids, user_id)
  -- hydrate ids
  local bookQuery = [[{
    query ($ids: [Int!], $userId: Int!) {
      books(where: { _id: { _in: $ids }}) {
        ...BookParts
      }
    }
  }]] .. book_fragment

  local books = self:query(bookQuery, { ids = ids, userId = user_id })

  if books and #books > 1 then
    local id_order = {}

    for i,v in ipairs(ids) do
      id_order[i] = v
    end

    -- sort books by original ID order
    table.sort(books, function (a, b)
      return id_order[a.id] < id_order[b.id]
    end)
  end

  return books
end

function HardcoverApi:hydrateBookFromEdition(edition_id, user_id)
  local editionSearch = [[
    query ($id Int!, $userId: Int!) {
      editions(where: { id: { _eq: $id }}) {
        ...EditionParts
      }
    }]] .. edition_fragment

  local editions = self:query(editionSearch, { id = edition_id, userId = user_id })
  if editions and editions.editions and #editions.editions > 0 then
    return self:normalizedEdition(editions.editions[1])
  end
end

function HardcoverApi:findBookBySlug(slug, user_id)
  local slugSearch = [[
    query ($slug: String!, $userId: Int!) {
      books(where: { slug: { _eq: $slug }}) {
        ...BookParts
      }
    }]] .. book_fragment

  local books = self:query(slugSearch, { slug = slug, userId = user_id })
  if books and books.books and #books.books > 0 then
    return books.books[1]
  end
end

function HardcoverApi:findEditions(book_id, user_id)
  local edition_search = [[
    query ($id: Int!, $userId: Int!) {
      editions(where: { book_id: { _eq: $id }, _or: [{edition_format: { _is_null: true }}, {edition_format: { _nin: ["Audio CD", "Audiobook", "Audio Cassette", "Audible Audio"] }} ]},
      limit: 50,
      order_by: { users_count: desc_nulls_last }) {
        ...EditionParts
      }
    }]] .. edition_fragment

  local editions = self:query(edition_search, { id = book_id, userId = user_id })
  if not editions or not editions.editions then return end
  local edition_list = editions.editions

  if #edition_list > 1 then
    -- prefer editions with user reads
    local edition_ids = {}
    for _,edition in ipairs(edition_list) do
      table.insert(edition_ids, edition.id)
    end

    local read_search = [[
      query ($ids: [Int!], $userId: Int!) {
        user_books(where: { edition_id: { _in: $ids }, user_id: { _eq: $userId }}) {
          edition_id
        }
      }
    ]]

    local read_editions = self:query(read_search, { ids = edition_ids, userId = user_id })
    local read_index = {}
    for _, read in ipairs(read_editions) do
      read_index[read.edition_id] = true
    end

    table.sort(edition_list,function (a, b)
      -- sort by user reads
      local read_a = read_index[a.id]
      local read_b = read_index[b.id]

      if read_a ~= read_b then
        return read_a == true
      end

      if a.users_count ~= b.users_count then
        return a.users_count > b.users_count
      end
    end)

  end

  local mapped_results = {}
  for _, edition in ipairs(edition_list) do
    table.insert(mapped_results, self:normalizedEdition(edition))
  end
  return mapped_results
end

-- TODO: determine what needs to be saved
  -- Adding a new book read only requires a book, but implies an edition
    -- starting progress only requires a book id. Edition ID is optional
    -- update book progress requires an id. The previous status id?
function HardcoverApi:search(title, author, userId, page)
  page = page or 1
  local query = [[{
    query ($query: String!, $page: Int!) {
      search(query: $query, per_page: 25, page: $page, query_type: "Book") {
        ids
      }
    }]]
  local search = title .. " " .. author
  local results = self:query(query, { query = search, page = page})
  if not results then
    return {}
  end

  local ids = {}

  for i,v in ipairs(results) do
    table.insert(ids, v.id)
  end

  return self:hydrateBooks(ids, userId)
end

function HardcoverApi:findBookByIdentifiers(identifiers, user_id)
  local isbnKey

  if identifiers.edition_id then
    local book = self:hydrateBookFromEdition(identifiers.edition_id, user_id)
    if book then
      return book
    end
  end

  if identifiers.book_slug then
    local book = self:findBookBySlug({ identifiers.book_slug }, user_id)
    if book then
      return book
    end
  end

  if identifiers.isbn_13 then
    isbnKey = 'isbn_13'
  elseif identifiers.isbn_10 then
    isbnKey = 'isbn_10'
  end

  if isbnKey then
    local editionSearch = [[
      query ($isbn: String!, $userId: Int!) {
        editions(where: { ]] .. isbnKey ..  [[: { _eq: $isbn }}) {
          ...EditionParts
        }
      }]] .. edition_fragment

    local editions = self:query(editionSearch, { isbn = tostring(identifiers[isbnKey]), userId = user_id  })
    if editions and editions.editions and #editions.editions > 0 then
      return self:normalizedEdition(editions.editions[1])
    end
  end
end

function HardcoverApi:normalizedEdition(edition)
  local result = edition.book

  result.edition_id = edition.id
  result.edition_format = edition.edition_format
  result.cached_image = edition.cached_image
  result.publisher = edition.publisher
  if edition.release_date then
    local year = edition.release_date:match("^(%d%d%d%d)-")
    result.release_year = year
  else
    result.release_year = nil
  end
  result.reads = edition.reads
  result.pages = edition.pages
  result.filetype = edition.edition_format or "physical book"
  result.users_count = edition.users_count

  return result
end


function HardcoverApi:findBooks(title, author, userId)
  local variables = {
    userId = userId
  }

  if not title or string.match(title, "^%s*$") then
    return {}
  end

  --handling author vs title searching
  -- prefer matching author
  -- prefer books on user lists
  local queryString = [[
    query ($title: String!, $userId: Int!) {
      books(
        limit: 50
        where: { title: { _ilike: $title }}
        order_by: { users_read_count: desc_nulls_last }
      ) {
        ...BookParts
      }
    }
  ]] .. book_fragment

  variables.title = "%" .. escapeLike(title:gsub(":.+", ""):gsub("^%s+", ""):gsub("%s+$", "")) .. "%"

  local books = self:query(queryString, variables)
  if not books then
    return
  end

  sortBooks(books.books, author)

  return books.books
end

function sortBooks(list, author)
  local lower_author = author:lower()
  -- split authors by ampersand, comma, trim
  local index = {}

  -- index books before sorting
  for _i, b in ipairs(list) do
    local r = {
      user_read = b.user_books.id ~= nil,
      author = false
    }
    -- TODO contributions may be an array of { author: {...}}
    if b.contributions.author then
      r.author = b.contributions.author.name:lower() == lower_author
      if not r.author then
        for j,a in b.contributions.author.alternate_names do
          if a:lower() == lower_author then
            r.author = true
            break
          end
        end
      end
    end

    index[b.id] = r
  end

  table.sort(list, function (a, b)
    -- sort by user reads
    local ia = index[a.id]
    local ib = index[b.id]

    if ia.user_read ~= ib.user_read then
      return ia.user_read
    end

    if ia.author ~= ib.author then
      return ia.author == true
    end

    if a.users_read_count ~= b.users_read_count then
      return a.users_read_count > b.users_read_count
    end

    return a.title < b.title
  end)
end

function HardcoverApi:updatePage(edition, page)
 -- may be edition specific
--mutation UpdateBookProgress($id: Int!, $pages: Int, $editionId: Int, $startedAt: date) {
--  update_user_book_read(id: $id, object: {
--    progress_pages: $pages,
--    edition_id: $editionId,
--    started_at: $startedAt,
--  }) {
--    id
--  }
--}


end

function HardcoverApi:updateRead(book_id, status_id, privacy_setting_id)
  local query = [[
    mutation ($object: UserBookCreateInput!) {
      insert_user_book(object: $object) {
        error
        user_book {
          ...UserBookParts
        }
      }
    }
  ]] .. user_book_fragment

  local update_args = {
    book_id = book_id,
    privacy_setting_id = privacy_setting_id or 1,
    status_id = status_id
  }
  local result = self:query(query, { object = update_args })
  if result and result.insert_user_book then
    return result.insert_user_book.user_book
  end
end

function HardcoverApi:removeRead(user_book_id)
  local query = [[
    mutation($id: Int!) {
      delete_user_book(id: $id) {
        id
      }
    }
  ]]
  return self:query(query, { id = user_book_id })
end

--mutation StartBookProgress($bookId: Int!, $pages: Int, $editionId: Int, $startedAt: date) {
--  insert_user_book_read(user_book_id: $bookId, user_book_read: {
--    progress_pages: $pages,
--    edition_id: $editionId,
--    started_at: $startedAt,
--  }) {
--    id
--  }
--}

-- status id 2
--end

function HardcoverApi:setRating(edition)
end

function HardcoverApi:findUserBook(book_id, user_id)
  -- this may not be adequate, as (it's possible) there could be more than one read in progress? Maybe?
  local read_query = [[
    query ($id: Int!, $userId: Int!) {
      user_books(where: { book_id: { _eq: $id }, user_id: { _eq: $userId }}) {
        ...UserBookParts
      }
    }
  ]] .. user_book_fragment

  local results = self:query(read_query, { id = book_id, userId = user_id })
  if not results or not results.user_books then
    return {}
  end

  return results.user_books[1]
end

-- most recent?
function HardcoverApi:findUserBookRead(edition_id, user_id)
end


function HardcoverApi:me()
  return self:query("{ me { id, name }}").me[1]
end

return HardcoverApi
