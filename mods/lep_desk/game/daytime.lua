-- The time of day at the desk: four times to set and a switch between a
-- running time, always day and always night. It applies to the whole
-- world.

local load = lep_core.loader("lep_desk")
local daytime = load("src/daytime")
local S = core.get_translator("lep_desk")

local STORAGE_KEY = "daytime"
local mod_storage = core.get_mod_storage()

local state = daytime.normalize(core.deserialize(mod_storage:get_string(STORAGE_KEY)))

local function current_speed()
	return tonumber(core.settings:get("time_speed")) or daytime.DEFAULT_SPEED
end

local function apply(steps)
	for _, step in ipairs(steps) do
		if step.op == "set_time" then
			core.set_timeofday(step.time)
		elseif step.op == "set_speed" then
			-- The engine reads this setting all the time, so the change
			-- works at once and for all players.
			core.settings:set("time_speed", tostring(step.speed))
		end
	end
end

local function change(new_state, steps)
	state = new_state
	mod_storage:set_string(STORAGE_KEY, core.serialize(state))
	apply(steps)
	lep_desk.refresh()
end

--- Returns the mode of the time of day: "running", "day" or "night".
function lep_desk.get_time_mode()
	return state.mode
end

-- After a restart the world is put back into its mode.
core.register_on_mods_loaded(function()
	apply(daytime.restore(state))
end)

local GROUP = S("Time of day")

local TIMES = {
	{ id = "morning", title = S("Morning"), done = S("It is morning now.") },
	{ id = "noon", title = S("Noon"), done = S("It is noon now.") },
	{ id = "evening", title = S("Evening"), done = S("It is evening now.") },
	{ id = "night", title = S("Night"), done = S("It is night now.") },
}

for _, entry in ipairs(TIMES) do
	lep_desk.register_action("lep_desk:time_" .. entry.id, {
		title = entry.title,
		privilege = lep_desk.PRIV_TIME,
		needs_targets = false,
		group = GROUP,
		run = function()
			change(daytime.set_time(state, entry.id))
			return entry.done
		end,
	})
end

local MODES = {
	{ id = daytime.RUNNING, title = S("Time runs"), done = S("The time runs.") },
	{ id = daytime.DAY, title = S("Always day"), done = S("It stays day.") },
	{ id = daytime.NIGHT, title = S("Always night"), done = S("It stays night.") },
}

for _, entry in ipairs(MODES) do
	lep_desk.register_action("lep_desk:time_mode_" .. entry.id, {
		title = entry.title,
		privilege = lep_desk.PRIV_TIME,
		needs_targets = false,
		group = GROUP,
		is_active = function()
			return state.mode == entry.id
		end,
		run = function()
			change(daytime.set_mode(state, entry.id, current_speed()))
			return entry.done
		end,
	})
end
