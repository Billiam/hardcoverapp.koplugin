local Book = {}
local reading_format_labels = {
  "Physical Book",
  "Audiobook",
  nil,
  "E-Book"
}

local function isbnChecksumValid(isbn)
  if #isbn == 10 then
    local sum = 0

    for index = 1, 10 do
      local char = isbn:sub(index, index)
      local digit = char == "X" and 10 or tonumber(char)
      if not digit or (digit == 10 and index ~= 10) then
        return false
      end
      sum = sum + digit * (11 - index)
    end

    return sum % 11 == 0
  elseif #isbn == 13 and isbn:match("^%d+$") then
    local sum = 0

    for index = 1, 13 do
      local digit = tonumber(isbn:sub(index, index))
      sum = sum + digit * (index % 2 == 0 and 3 or 1)
    end

    return sum % 10 == 0
  end

  return false
end

function Book:readingFormat(format_id)
  if not format_id then
    return
  end

  return reading_format_labels[format_id]
end

function Book:editionFormatName(edition_format, format_id)
  if edition_format and edition_format ~= "" then
    return edition_format
  end

  return self:readingFormat(format_id)
end

function Book:normalizeIsbn(value)
  if not value then
    return
  end

  local isbn = string.upper(value):gsub("[%s%-]", "")
  if not isbn:match("^[%dX]+$") or not isbnChecksumValid(isbn) then
    return
  end

  return isbn
end

function Book:parseIdentifiers(identifiers)
  local result = {}

  if not identifiers then
    return result
  end

  for line in string.lower(identifiers):gmatch("[^\r\n]+") do
    -- Check for hardcover:, hardcover-slug: and hardcover-edition:.
    local hc = string.match(line, "hardcover%s*:%s*([%w_-]+)")
      or string.match(line, "hardcover%-slug%s*:%s*([%w_-]+)")
    if hc then
      result.book_slug = hc
    end

    local hc_edition = string.match(line, "hardcover%-edition%s*:%s*(%d+)")
    if hc_edition then
      result.edition_id = hc_edition
    end

    local isbn_source = line
      :gsub("hardcover%-edition%s*:%s*[%w_-]+", " ")
      :gsub("hardcover%-slug%s*:%s*[%w_-]+", " ")
      :gsub("hardcover%s*:%s*[%w_-]+", " ")

    for candidate in isbn_source:gmatch("[%dXx][%dXx%s%-]*[%dXx]") do
      local isbn = self:normalizeIsbn(candidate)
      if isbn then
        if #isbn == 13 then
          result.isbn_13 = isbn
        elseif #isbn == 10 then
          result.isbn_10 = isbn
        end
      end
    end
  end

  return result
end

return Book
