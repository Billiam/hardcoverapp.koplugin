local ReviewFormat = {}

local function paragraph_block(text)
  return {
    data = {},
    type = "paragraph",
    object = "block",
    children = { { text = text, object = "text" } }
  }
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
      table.insert(children, paragraph_block(string.sub(plain_text, last_end)))
      break
    end
    table.insert(children, paragraph_block(string.sub(plain_text, last_end, start_idx - 1)))
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
