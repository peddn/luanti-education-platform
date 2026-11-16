-- The time of day as the teacher sets it. Pure Lua, no engine calls.
--
-- The world is in one of three modes: the time runs, or it stands still
-- at noon or at midnight. The functions return the new state and a list
-- of steps for the game layer:
--   { op = "set_time", time = 0.5 }    time of day, 0 to 1
--   { op = "set_speed", speed = 72 }   how fast the time runs, 0 = not

local daytime = {}

daytime.RUNNING = "running"
daytime.DAY = "day"
daytime.NIGHT = "night"

-- The speed of the time in a world nobody changed.
daytime.DEFAULT_SPEED = 72

-- The times a teacher can set, as time of day from 0 to 1.
daytime.TIMES = { morning = 0.25, noon = 0.5, evening = 0.75, night = 0 }

-- Where the time stands still.
local FROZEN_AT = { [daytime.DAY] = daytime.TIMES.noon, [daytime.NIGHT] = daytime.TIMES.night }

--- Returns a usable state from stored data: mode and the speed to go back
-- to when the time runs again.
function daytime.normalize(data)
	local state = { mode = daytime.RUNNING, speed = daytime.DEFAULT_SPEED }
	if type(data) ~= "table" then
		return state
	end
	if data.mode == daytime.DAY or data.mode == daytime.NIGHT then
		state.mode = data.mode
	end
	if type(data.speed) == "number" and data.speed > 0 then
		state.speed = data.speed
	end
	return state
end

--- Switches the mode.
-- @param current_speed The speed of the time right now.
-- @return new state, steps
function daytime.set_mode(state, mode, current_speed)
	assert(mode == daytime.RUNNING or mode == daytime.DAY or mode == daytime.NIGHT,
		"unknown mode '" .. tostring(mode) .. "'")
	local speed = state.speed
	-- Remember how fast the time ran before it was stopped.
	if state.mode == daytime.RUNNING and type(current_speed) == "number"
			and current_speed > 0 then
		speed = current_speed
	end
	local new_state = { mode = mode, speed = speed }
	if mode == daytime.RUNNING then
		return new_state, { { op = "set_speed", speed = speed } }
	end
	return new_state, {
		{ op = "set_time", time = FROZEN_AT[mode] },
		{ op = "set_speed", speed = 0 },
	}
end

--- Sets the time. A time that stood still runs again afterwards:
-- "always day" at midnight would make no sense.
-- @param time_id "morning", "noon", "evening" or "night"
-- @return new state, steps
function daytime.set_time(state, time_id)
	local time = assert(daytime.TIMES[time_id], "unknown time '" .. tostring(time_id) .. "'")
	local steps = { { op = "set_time", time = time } }
	if state.mode ~= daytime.RUNNING then
		steps[#steps + 1] = { op = "set_speed", speed = state.speed }
	end
	return { mode = daytime.RUNNING, speed = state.speed }, steps
end

--- Returns the steps that bring the world back into its mode after a
-- start of the server. A running time is left alone.
function daytime.restore(state)
	if state.mode == daytime.RUNNING then
		return {}
	end
	return {
		{ op = "set_time", time = FROZEN_AT[state.mode] },
		{ op = "set_speed", speed = 0 },
	}
end

return daytime
