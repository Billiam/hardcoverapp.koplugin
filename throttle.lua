local time = require("ui/time")
local UIManager = require("ui/uimanager")

local throttle = function(seconds, action)
  local args = nil
  local previous_execute_at = nil
  local is_scheduled = false
  local result = nil
  local request_trailing = false

  local scheduled_action

  local execute = function()
    previous_execute_at = time:now()
    result = action(unpack(args, 1, args.n))

    is_scheduled = true
    UIManager:scheduleIn(seconds, scheduled_action)
  end

  scheduled_action = function()
    -- handle timer triggering early

    local now = time:now()
    local next_execute = previous_execute_at + seconds
    if next_execute > now then
      UIManager:scheduleIn(next_execute - now, scheduled_action)
      is_scheduled = true
    else
      is_scheduled = false

      if request_trailing then
        request_trailing = false
        execute()
      end

      if not is_scheduled then
        -- This check is needed because action can recursively call debounced_action_wrapper
        args = nil
      end
    end
  end

  local throttled_action_wrapper = function(...)
    args = table.pack(...)
    if is_scheduled then
      request_trailing = true
    else
      execute()
    end
    return result
  end

  local cancel = function()
    is_scheduled = false
    return UIManager:unschedule(scheduled_action)
  end

  return throttled_action_wrapper, cancel
end

return throttle
