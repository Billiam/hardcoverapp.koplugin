local BookSearch = {}

local MIN_TITLE_SIMILARITY = 0.72
local MIN_MATCH_SCORE = 0.78
local MIN_TITLE_ONLY_SIMILARITY = 0.90
local NEAR_EXACT_TITLE_SIMILARITY = 0.96

local function trim(value)
  if not value then
    return value
  end

  return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function collapseWhitespace(value)
  return trim(value):gsub("%s+", " ")
end

local function utf8Chars(value)
  local chars = {}
  local index = 1

  while index <= #value do
    local first = value:byte(index)
    local length = 1

    if first >= 240 then
      length = 4
    elseif first >= 224 then
      length = 3
    elseif first >= 192 then
      length = 2
    end

    table.insert(chars, value:sub(index, index + length - 1))
    index = index + length
  end

  return chars
end

local function containsHangul(value)
  if not value then
    return false
  end

  for _, char in ipairs(utf8Chars(value)) do
    local first, second, third = char:byte(1, 3)
    if (first == 234 and second and second >= 176)
      or first == 235
      or first == 236
      or (first == 237 and second and second <= 158 and third)
    then
      return true
    end
  end

  return false
end

local function findLast(value, needle)
  local found
  local start = 1

  while true do
    local index = value:find(needle, start, true)
    if not index then
      return found
    end
    found = index
    start = index + #needle
  end
end

local title_qualifier_markers = {
  "개정판",
  "증보판",
  "특별판",
  "기념판",
  "소장판",
  "보급판",
  "큰글자",
  "양장본",
  "양장",
  "합본",
  "완결",
  "세트",
  "에디션",
  "리커버",
  "전자책",
  "오디오북",
  "부제",
  "시리즈",
}

local function isDiscardableTitleQualifier(value)
  local compact = collapseWhitespace(value):gsub("%s+", "")

  if compact:match("^제%d+권$") or compact:match("^%d+권$")
    or compact:match("^%d$") or compact:match("^%d%d$")
    or compact == "상" or compact == "중" or compact == "하"
    or compact == "장편소설"
  then
    return true
  end

  for _, marker in ipairs(title_qualifier_markers) do
    if compact:find(marker, 1, true) then
      return true
    end
  end

  return false
end

local function stripTrailingTitleQualifier(value)
  local pairs = {
    { "(", ")" },
    { "[", "]" },
    { "【", "】" },
  }

  for _, pair in ipairs(pairs) do
    local open, close = pair[1], pair[2]
    if value:sub(-#close) == close then
      local open_index = findLast(value, open)
      if open_index then
        local qualifier = value:sub(open_index + #open, #value - #close)
        if isDiscardableTitleQualifier(qualifier) then
          return trim(value:sub(1, open_index - 1)), true
        end
      end
    end
  end

  return value, false
end

local function stripKoreanSubtitle(value)
  local separators = { ":", "：", " - ", " – ", " — " }
  local first_separator

  for _, separator in ipairs(separators) do
    local index = value:find(separator, 1, true)
    if index and index > 1 and (not first_separator or index < first_separator) then
      first_separator = index
    end
  end

  if first_separator then
    return trim(value:sub(1, first_separator - 1))
  end

  return value
end

local primary_author_roles = { "지은이", "글쓴이", "지음", "저자", "저", "글" }
local secondary_author_roles = { "번역자", "옮긴이", "옮김", "번역", "역자", "그림" }

local function removeAuthorRole(value, role)
  local original = value

  value = value:gsub("%(%s*" .. role .. "%s*%)", " ")
  value = value:gsub("^%s*" .. role .. "%s*[:：]%s*", "")
  value = value:gsub("%s+" .. role .. "%s*$", "")

  -- Multi-syllable roles are also commonly appended without whitespace.
  if #role >= 6 then
    value = value:gsub(role .. "%s*$", "")
  end

  if trim(value) == role then
    value = ""
  end

  return collapseWhitespace(value), value ~= original
end

local function authorPart(value)
  local normalized = value

  for _, role in ipairs(primary_author_roles) do
    local changed
    normalized, changed = removeAuthorRole(normalized, role)
    if changed then
      return normalized, "primary"
    end
  end

  for _, role in ipairs(secondary_author_roles) do
    local changed
    normalized, changed = removeAuthorRole(normalized, role)
    if changed then
      return normalized, "secondary"
    end
  end

  return collapseWhitespace(normalized), "unmarked"
end

local ignored_comparison_chars = {
  [" "] = true,
  ["\t"] = true,
  ["\r"] = true,
  ["\n"] = true,
  ["."] = true,
  [","] = true,
  [":"] = true,
  [";"] = true,
  ["-"] = true,
  ["_"] = true,
  ["'"] = true,
  ['"'] = true,
  ["("] = true,
  [")"] = true,
  ["["] = true,
  ["]"] = true,
  ["{"] = true,
  ["}"] = true,
  ["·"] = true,
  ["・"] = true,
  ["—"] = true,
  ["–"] = true,
  ["："] = true,
  ["【"] = true,
  ["】"] = true,
}

local function comparisonChars(value)
  local chars = {}

  for _, char in ipairs(utf8Chars(string.lower(value or ""))) do
    if not ignored_comparison_chars[char] then
      table.insert(chars, char)
    end
  end

  return chars
end

local function textSimilarity(left, right)
  local left_chars = comparisonChars(left)
  local right_chars = comparisonChars(right)

  if #left_chars == 0 or #right_chars == 0 then
    return 0
  end

  local left_string = table.concat(left_chars)
  local right_string = table.concat(right_chars)
  if left_string == right_string then
    return 1
  end

  local containment = 0
  if left_string:find(right_string, 1, true) or right_string:find(left_string, 1, true) then
    containment = math.min(#left_chars, #right_chars) / math.max(#left_chars, #right_chars)
  end

  if #left_chars == 1 or #right_chars == 1 then
    return containment
  end

  local left_bigrams = {}
  local right_bigrams = {}
  for index = 1, #left_chars - 1 do
    local bigram = left_chars[index] .. left_chars[index + 1]
    left_bigrams[bigram] = (left_bigrams[bigram] or 0) + 1
  end
  for index = 1, #right_chars - 1 do
    local bigram = right_chars[index] .. right_chars[index + 1]
    right_bigrams[bigram] = (right_bigrams[bigram] or 0) + 1
  end

  local overlap = 0
  for bigram, count in pairs(left_bigrams) do
    overlap = overlap + math.min(count, right_bigrams[bigram] or 0)
  end

  local dice = (2 * overlap) / (#left_chars + #right_chars - 2)
  return math.max(containment, dice)
end

local function appendUnique(values, value)
  value = collapseWhitespace(value or "")
  if value == "" then
    return
  end

  for _, existing in ipairs(values) do
    if existing == value then
      return
    end
  end

  table.insert(values, value)
end

local function splitAuthors(value)
  local authors = {}

  for part in (value or ""):gmatch("([^,;/\r\n]+)") do
    appendUnique(authors, part)
  end

  return authors
end

local function resultAuthors(book)
  local authors = {}
  local contributions = book and book.contributions

  if type(contributions) ~= "table" then
    return authors
  end

  if type(contributions.author) == "string" then
    appendUnique(authors, contributions.author)
  elseif type(contributions.author) == "table" then
    if contributions.author.name then
      appendUnique(authors, contributions.author.name)
    else
      for _, author in ipairs(contributions.author) do
        if type(author) == "string" then
          appendUnique(authors, author)
        elseif type(author) == "table" then
          appendUnique(authors, author.name)
        end
      end
    end
  end

  for _, contribution in ipairs(contributions) do
    if type(contribution) == "table" then
      if type(contribution.author) == "string" then
        appendUnique(authors, contribution.author)
      elseif type(contribution.author) == "table" then
        appendUnique(authors, contribution.author.name)
      end
    end
  end

  return authors
end

local function bestSimilarity(left_values, right_values)
  local best = 0

  for _, left in ipairs(left_values) do
    for _, right in ipairs(right_values) do
      best = math.max(best, textSimilarity(left, right))
    end
  end

  return best
end

function BookSearch:normalizeTitle(title)
  if not title or not containsHangul(title) then
    return title
  end

  local normalized = collapseWhitespace(title)
  local changed = true

  while changed do
    normalized, changed = stripTrailingTitleQualifier(normalized)
  end

  normalized = stripKoreanSubtitle(normalized)
  normalized = normalized:gsub("%s+제%s*%d+%s*권%s*$", "")
  normalized = normalized:gsub("%s+%d+%s*권%s*$", "")
  normalized = collapseWhitespace(normalized)

  return normalized ~= "" and normalized or title
end

function BookSearch:normalizeAuthor(author)
  if not author or not containsHangul(author) then
    return author
  end

  local parts = {}
  local has_primary_or_unmarked = false

  for value in author:gmatch("([^,;/\r\n]+)") do
    local name, role = authorPart(value)
    if name ~= "" then
      table.insert(parts, { name = name, role = role })
      if role ~= "secondary" then
        has_primary_or_unmarked = true
      end
    end
  end

  local authors = {}
  for _, part in ipairs(parts) do
    if not has_primary_or_unmarked or part.role ~= "secondary" then
      appendUnique(authors, part.name)
    end
  end

  if #authors == 0 then
    return author
  end

  return table.concat(authors, ", ")
end

function BookSearch:metadata(title, author)
  local korean = containsHangul(title)
  local normalized_title = korean and self:normalizeTitle(title) or title
  local normalized_author = korean and self:normalizeAuthor(author) or author

  return {
    original_title = title,
    original_author = author,
    normalized_title = normalized_title,
    normalized_author = normalized_author,
    is_korean = korean,
    normalized_changed = normalized_title ~= title or normalized_author ~= author,
  }
end

function BookSearch:matchScore(metadata, book)
  if not metadata or not book or not book.title then
    return 0, false
  end

  local input_titles = {}
  appendUnique(input_titles, metadata.original_title)
  appendUnique(input_titles, metadata.normalized_title)

  local result_titles = { book.title }
  appendUnique(result_titles, self:normalizeTitle(book.title))
  local title_score = bestSimilarity(input_titles, result_titles)

  local input_authors = splitAuthors(metadata.normalized_author or metadata.original_author)
  local book_authors = resultAuthors(book)
  local author_score = bestSimilarity(input_authors, book_authors)
  local has_author = #input_authors > 0
  local author_scripts_differ = false

  if has_author and #book_authors > 0 then
    local input_has_hangul = containsHangul(metadata.normalized_author or metadata.original_author)
    for _, author in ipairs(book_authors) do
      if input_has_hangul ~= containsHangul(author) then
        author_scripts_differ = true
        break
      end
    end
  end

  local score = title_score
  if has_author then
    score = title_score * 0.75 + author_score * 0.25
  end

  local accepted
  if has_author and #book_authors > 0 then
    accepted = (title_score >= MIN_TITLE_SIMILARITY and score >= MIN_MATCH_SCORE)
      or (title_score >= NEAR_EXACT_TITLE_SIMILARITY and author_scripts_differ)
  elseif has_author then
    accepted = title_score >= NEAR_EXACT_TITLE_SIMILARITY
  else
    accepted = title_score >= MIN_TITLE_ONLY_SIMILARITY
  end

  return score, accepted, title_score, author_score
end

function BookSearch:findBestMatch(metadata, books)
  local best_book
  local best_score = -1

  for _, book in ipairs(books or {}) do
    local score, accepted = self:matchScore(metadata, book)
    if accepted and score > best_score then
      best_book = book
      best_score = score
    end
  end

  return best_book, best_score
end

return BookSearch
