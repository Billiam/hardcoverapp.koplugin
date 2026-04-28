local ReviewFormat = {}

local function paragraph_block(text)
  return {
    data = {},
    type = "paragraph",
    object = "block",
    children = { { text = text, object = "text" } }
  }
end

local function has_non_whitespace(text)
  return not string.match(text, "^%s*$")
end

function ReviewFormat.buildSlateDocument(plain_text)
  if plain_text == nil then
    return nil
  end
  if string.match(plain_text, "^%s*$") then
    return nil
  end

  local children = {}
  local last_end = 1
  while true do
    local start_idx, end_idx = string.find(plain_text, "\n\n", last_end, true)
    if not start_idx then
      local segment = string.sub(plain_text, last_end)
      if has_non_whitespace(segment) then
        table.insert(children, paragraph_block(segment))
      end
      break
    end
    local segment = string.sub(plain_text, last_end, start_idx - 1)
    if has_non_whitespace(segment) then
      table.insert(children, paragraph_block(segment))
    end
    last_end = end_idx + 1
  end

  return {
    document = {
      object = "document",
      children = children
    }
  }
end

return ReviewFormat
