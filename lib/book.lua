local Book = {}

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

      if str then
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
