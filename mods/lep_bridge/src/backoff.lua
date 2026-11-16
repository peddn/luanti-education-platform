-- How long to wait before trying again. Pure Lua, no engine calls.

local backoff = {}

-- Seconds to wait after the first, second, ... failure in a row.
backoff.STEPS = { 1, 2, 5, 10, 30, 60 }

--- Returns the seconds to wait after `failures` failed tries in a row.
-- The pauses grow, so a backend that is down is not flooded, and stay at
-- one minute, so the world is back soon after the backend is.
function backoff.delay(failures)
	if type(failures) ~= "number" or failures < 1 then
		return 0
	end
	return backoff.STEPS[math.min(math.floor(failures), #backoff.STEPS)]
end

return backoff
