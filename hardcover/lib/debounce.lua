local time = require("ui/time")
local UIManager = require("ui/uimanager")

local debounce = function(seconds, action)
  local args = nil
  local previous_call_at = nil

  local scheduled_action

  local execute = function()
    action(table.unpack(args, 1, args.n))
  end

  scheduled_action = function()
    -- handle timer triggering early
    local now = time:now()
    local next_execute = previous_call_at + seconds
    if next_execute > now then
      UIManager:scheduleIn(next_execute - now, scheduled_action)
    else
      execute()
      args = nil
    end
  end

  local debounced_action_wrapper = function(...)
    previous_call_at = time:now()

    args = table.pack(...)
    UIManager:unschedule(scheduled_action)
    UIManager:scheduleIn(seconds, scheduled_action)
  end

  local cancel = function()
    return UIManager:unschedule(scheduled_action)
  end

  return debounced_action_wrapper, cancel
end

return debounce
