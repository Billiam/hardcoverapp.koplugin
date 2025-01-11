local TableUtil = {}

function TableUtil.dig(t, ...)
  local result = t

  for _, k in ipairs({ ... }) do
    result = result[k]
    if result == nil then
      return nil
    end
  end

  return result
end

function TableUtil.contains(t, value)
  if not t then
    return false
  end

  for _, v in ipairs(t) do
    if v == value then
      return true
    end
  end

  return false
end

function TableUtil.binSearch(t, value)
  local start_i = 1
  local end_i = #t

  while start_i <= end_i do
    local mid_i = math.floor((start_i + end_i) / 2)
    local mid_val = t[mid_i]

    if mid_val == value then
      while t[mid_i] == value do
        mid_i = mid_i - 1
      end
      return mid_i + 1
    end

    if mid_val > value then
      end_i = mid_i - 1
    else
      start_i = mid_i + 1
    end
  end

  return start_i
end

return TableUtil
