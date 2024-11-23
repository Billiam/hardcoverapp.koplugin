local TableUtil = {}

function TableUtil.dig(t, ...)
  local result = t

  for _, k in ipairs(arg) do
    result = result[k]
    if result == nil then
      return nil
    end
  end

  return result
end

return TableUtil
