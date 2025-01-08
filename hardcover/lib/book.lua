local Book = {}
local reading_format_labels = {
  "Physical Book",
  "Audiobook",
  nil,
  "E-Book"
}

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

function Book:parseIdentifiers(identifiers)
  local result = {}

  if not identifiers then
    return result
  end

  for line in string.lower(identifiers):gmatch("%s*([^%s]+)%s*") do
    -- check for hardcover: and hardcover-edition:
    local hc = string.match(line, "hardcover:([%w_-]+)")
    if hc then
      result.book_slug = hc
    end

    local hc_edition = string.match(line, "hardcover%-edition:(%d+)")

    if hc_edition then
      result.edition_id = hc_edition
    end

    if not hc and not hc_edition then
      -- strip prefix
      local str = string.gsub(line, "^[^%s]+%s*:%s*", "")
      str = string.gsub(str, "-", "")

      if str and string.find(str, "^%d+$") then
        local len = #str

        if len == 13 then
          result.isbn_13 = str
        elseif len == 10 then
          result.isbn_10 = str
        end
      end
    end
  end
  return result
end

return Book
