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
  --logger.warn(json.encode(requestBody))
  --logger.warn(responseBody, code)
  if code == 200 then
    local data = json.decode(table.concat(responseBody), json.decode.simple)
    if data.data then
      return data.data
    end
  end
end

function HardcoverApi:mutation(query, args)
end

-- TODO: determine what needs to be saved
  -- Adding a new book read only requires a book, but implies an edition
    -- starting progress only requires a book id. Edition ID is optional
    -- update book progress requires an id. The previous status id?

function HardcoverApi:findBook(title, author, identifiers, userId)
  local variables = {
    userId = userId
  }
  local isbnKey

  --if identifiers.isbn13 then
  --  variables.isbn13 = identifiers.isbn13
  --  isbnKey = 'isbn13'
  --elseif identifiers.isbn then
  --  variables.isbn = identifiers.isbn
  --  isbnKey = 'isbn'
  --end

  local queryResults = {}

  if isbnKey then
  -- TODO: where not audiobook
    local editionSearch = [[{
      query ($isbn) {
        editions(where: { ]] .. isbnKey ..  [[: { _eq: $isbn }}){
          id
          title
          release_year
          book_id
          publisher {
            name
          }
        }
      }
    }]]
    local editions = self:query(editionSearch, queryResults)
    if editions then
      return {
        edition = editions[1]
      }
    end
  end

  if not title then
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
      }
    }
  ]]
  variables.title = "%" .. escapeLike(title:gsub(":.+", ""):gsub("^%s+", ""):gsub("%s+$", "")) .. "%"

  local books = self:query(queryString, variables)
  if not books then
    return
  end

  sortBooks(books.books, author)

  --logger.warn(books.books)

  return {
    books = books.books
  }
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
      return ia.author
    end
    if a.users_read_count ~= b.users_read_count then
      return a.users_read_count > b.users_read_count
    end
    return a.title < b.title
  end)
end

function HardcoverApi:findEditions(book_id)
  if not book_id then
    return
  end

  --{"operationName":"FindEditionsForBook","variables":{"bookId":382700},"query":"query FindEditionsForBook($bookId: Int!) {\n  editions(where: {book_id: {_eq: $bookId}}, order_by: {users_count: desc}) {\n    ...EditionFragment\n    __typename\n  }\n}\n\nfragment EditionFragment on editions {\n  id\n  title\n  asin\n  isbn10: isbn_10\n  isbn13: isbn_13\n  releaseDate: release_date\n  releaseYear: release_year\n  pages\n  audioSeconds: audio_seconds\n  readingFormatId: reading_format_id\n  usersCount: users_count\n  cachedImage: cached_image\n  editionFormat: edition_format\n  editionInformation: edition_information\n  language {\n    id\n    language\n    code: code2\n    __typename\n  }\n  readingFormat: reading_format {\n    format\n    __typename\n  }\n  country {\n    name\n    __typename\n  }\n  publisher {\n    ...PublisherFragment\n    __typename\n  }\n  __typename\n}\n\nfragment PublisherFragment on publishers {\n  id\n  name\n  slug\n  editionsCount: editions_count\n  __typename\n}"}
  -- prefer books on users lists
  local queryString = [[{
    query ($bookId: Int!) {
      editions(limit: 10, where { book_id: { _eq: $bookId }}, order_by: [{users_read_count: desc_nulls_last}]) {
        id
        title
        release_year
        book_id
        publisher {
          name
        }
      }
    }
  }]]

  return self:query(queryString, { bookId = book_id })
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
-- progress is stored by edition ID. Need to know currrent page for edition
-- no way to match page to percent
function HardcoverApi:updateProgress(edition, progress)

end
function HardcoverApi:markReading(edition)
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
end
function HardcoverApi:markFinished(edition)
-- status id 3
--mutation FinishBookProgress($id: Int!, $pages: Int, $editionId: Int, $startedAt: date, $finishedAt: date) {
--  update_user_book_read(id: $id, object: {
--    progress_pages: $pages,
--    edition_id: $editionId,
--    started_at: $startedAt,
--    finished_at: $finishedAt,
--  }) {
--    id
--  }
--}
end
function HardcoverApi:setRating(edition)
end
function HardcoverApi:markDidNotFinish(edition)
  -- status id 5
end
--want to read: status id 1

function HardcoverApi:me()
  return self:query("{ me { id, name }}").me[1]
end


-- may not be needed since arguments may be passed as separate JSON
function escapeString(str)
  return str:gsub("\\", "\\\\"):gsub('"', '\\"')
end

function escapeLike(str)
  return str:gsub("%%", "\\%%"):gsub("_", "\\_")
end

-- find editions for book
--{"operationName":"FindEditionsForBook","variables":{"bookId":382700},"query":"query FindEditionsForBook($bookId: Int!) {\n  editions(where: {book_id: {_eq: $bookId}}, order_by: {users_count: desc}) {\n    ...EditionFragment\n    __typename\n  }\n}\n\nfragment EditionFragment on editions {\n  id\n  title\n  asin\n  isbn10: isbn_10\n  isbn13: isbn_13\n  releaseDate: release_date\n  releaseYear: release_year\n  pages\n  audioSeconds: audio_seconds\n  readingFormatId: reading_format_id\n  usersCount: users_count\n  cachedImage: cached_image\n  editionFormat: edition_format\n  editionInformation: edition_information\n  language {\n    id\n    language\n    code: code2\n    __typename\n  }\n  readingFormat: reading_format {\n    format\n    __typename\n  }\n  country {\n    name\n    __typename\n  }\n  publisher {\n    ...PublisherFragment\n    __typename\n  }\n  __typename\n}\n\nfragment PublisherFragment on publishers {\n  id\n  name\n  slug\n  editionsCount: editions_count\n  __typename\n}"}


--fragment EditionFragment on editions {
--  id
--  title
--  asin
--  isbn10: isbn_10
--  isbn13: isbn_13
--  releaseDate: release_date
--  releaseYear: release_year
--  pages
--  audioSeconds: audio_seconds
--  readingFormatId: reading_format_id
--  usersCount: users_count
--  cachedImage: cached_image
--  editionFormat: edition_format
--  editionInformation: edition_information
--  language {
--    id
--    language
--    code: code2
--    __typename
--  }
--  readingFormat: reading_format {
--    format
--    __typename
--  }
--  country {
--    name
--    __typename
--  }
--  publisher {
--    ...PublisherFragment
--    __typename
--  }
--  __typename
--}
--
--fragment PublisherFragment on publishers {
--  id
--  name
--  slug
--  editionsCount: editions_count
--  __typename
--}"

function HardcoverApi:findEditions()
  query = [[
query FindEditionsForBook($bookId: Int!) {
  editions(where: {book_id: {_eq: $bookId}}, order_by: {users_count: desc}) {

  }
}]]
end

return HardcoverApi

--{"operationName":"CreateUserBook",
-- "variables":
--  {"object":{"book_id":382700,"status_id":1,"privacy_setting_id":2}},
-- "query":"mutation CreateUserBook($object: UserBookCreateInput!) {\n  insertResponse: insert_user_book(object: $object) {\n    error\n    userBook: user_book {\n      ...UserBookFragment\n      __typename\n    }\n    __typename\n  }\n}\n\nfragment UserBookFragment on user_books {\n  id\n  bookId: book_id\n  editionId: edition_id\n  userId: user_id\n  statusId: status_id\n  rating\n  privacySettingId: privacy_setting_id\n  hasReview: has_review\n  edition {\n    ...EditionFragment\n    __typename\n  }\n  datesRead: user_book_reads {\n    ...UserBookReadFragment\n    __typename\n  }\n  __typename\n}\n\nfragment EditionFragment on editions {\n  id\n  title\n  asin\n  isbn10: isbn_10\n  isbn13: isbn_13\n  releaseDate: release_date\n  releaseYear: release_year\n  pages\n  audioSeconds: audio_seconds\n  readingFormatId: reading_format_id\n  usersCount: users_count\n  cachedImage: cached_image\n  editionFormat: edition_format\n  editionInformation: edition_information\n  language {\n    id\n    language\n    code: code2\n    __typename\n  }\n  readingFormat: reading_format {\n    format\n    __typename\n  }\n  country {\n    name\n    __typename\n  }\n  publisher {\n    ...PublisherFragment\n    __typename\n  }\n  __typename\n}\n\nfragment UserBookReadFragment on user_book_reads {\n  id\n  userBookId: user_book_id\n  startedAt: started_at\n  finishedAt: finished_at\n  editionId: edition_id\n  progress\n  progressPages: progress_pages\n  progressSeconds: progress_seconds\n  edition {\n    ...EditionFragment\n    __typename\n  }\n  __typename\n}\n\nfragment PublisherFragment on publishers {\n  id\n  name\n  slug\n  editionsCount: editions_count\n  __typename\n}"}
-- "mutation DestroyUserBook($id: Int!) {\n  deleteResponse: delete_user_book(id: $id) {\n    id\n    bookId: book_id\n    userId: user_id\n    __typename\n  }\n}"
-- (currently reading)
-- {object: {book_id: 382700, status_id: 2, privacy_setting_id: 1}}
--"mutation CreateUserBook($object: UserBookCreateInput!) {\n  insertResponse: insert_user_book(object: $object) {\n    error\n    userBook: user_book {\n      ...UserBookFragment\n      __typename\n    }\n    __typename\n  }\n}\n\nfragment UserBookFragment on user_books {\n  id\n  bookId: book_id\n  editionId: edition_id\n  userId: user_id\n  statusId: status_id\n  rating\n  privacySettingId: privacy_setting_id\n  hasReview: has_review\n  edition {\n    ...EditionFragment\n    __typename\n  }\n  datesRead: user_book_reads {\n    ...UserBookReadFragment\n    __typename\n  }\n  __typename\n}\n\nfragment EditionFragment on editions {\n  id\n  title\n  asin\n  isbn10: isbn_10\n  isbn13: isbn_13\n  releaseDate: release_date\n  releaseYear: release_year\n  pages\n  audioSeconds: audio_seconds\n  readingFormatId: reading_format_id\n  usersCount: users_count\n  cachedImage: cached_image\n  editionFormat: edition_format\n  editionInformation: edition_information\n  language {\n    id\n    language\n    code: code2\n    __typename\n  }\n  readingFormat: reading_format {\n    format\n    __typename\n  }\n  country {\n    name\n    __typename\n  }\n  publisher {\n    ...PublisherFragment\n    __typename\n  }\n  __typename\n}\n\nfragment UserBookReadFragment on user_book_reads {\n  id\n  userBookId: user_book_id\n  startedAt: started_at\n  finishedAt: finished_at\n  editionId: edition_id\n  progress\n  progressPages: progress_pages\n  progressSeconds: progress_seconds\n  edition {\n    ...EditionFragment\n    __typename\n  }\n  __typename\n}\n\nfragment PublisherFragment on publishers {\n  id\n  name\n  slug\n  editionsCount: editions_count\n  __typename\n}"


-- changing the edition of an existing book being read:edition
--"mutation UpdateUserBook($id: Int!, $object: UserBookUpdateInput!) {\n  updateResponse: update_user_book(id: $id, object: $object) {\n    error\n    userBook: user_book {\n      ...UserBookFragment\n      __typename\n    }\n    __typename\n  }\n}\n\nfragment UserBookFragment on user_books {\n  id\n  bookId: book_id\n  editionId: edition_id\n  userId: user_id\n  statusId: status_id\n  rating\n  privacySettingId: privacy_setting_id\n  hasReview: has_review\n  edition {\n    ...EditionFragment\n    __typename\n  }\n  datesRead: user_book_reads {\n    ...UserBookReadFragment\n    __typename\n  }\n  __typename\n}\n\nfragment EditionFragment on editions {\n  id\n  title\n  asin\n  isbn10: isbn_10\n  isbn13: isbn_13\n  releaseDate: release_date\n  releaseYear: release_year\n  pages\n  audioSeconds: audio_seconds\n  readingFormatId: reading_format_id\n  usersCount: users_count\n  cachedImage: cached_image\n  editionFormat: edition_format\n  editionInformation: edition_information\n  language {\n    id\n    language\n    code: code2\n    __typename\n  }\n  readingFormat: reading_format {\n    format\n    __typename\n  }\n  country {\n    name\n    __typename\n  }\n  publisher {\n    ...PublisherFragment\n    __typename\n  }\n  __typename\n}\n\nfragment UserBookReadFragment on user_book_reads {\n  id\n  userBookId: user_book_id\n  startedAt: started_at\n  finishedAt: finished_at\n  editionId: edition_id\n  progress\n  progressPages: progress_pages\n  progressSeconds: progress_seconds\n  edition {\n    ...EditionFragment\n    __typename\n  }\n  __typename\n}\n\nfragment PublisherFragment on publishers {\n  id\n  name\n  slug\n  editionsCount: editions_count\n  __typename\n}"
