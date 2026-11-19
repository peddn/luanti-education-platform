-- The reward table of this world: which item and how many per occasion,
-- and how many daily tasks are rewarded per day. A world is a group, so
-- this is the table of the group. Only this file knows where it is kept.

local load = lep_core.loader("lep_rewards")
local rewards = load("src/rewards")

local config = {}

local STORAGE_KEY = "table"
local mod_storage = core.get_mod_storage()

--- Returns true if an item exists in this world and can be given out.
function config.is_item(name)
	return core.registered_items[name] ~= nil and name ~= "" and name ~= "unknown"
		and name ~= "air" and name ~= "ignore"
end

-- The table is read when it is first needed: only then all mods are
-- loaded and their items known.
local current

local function get()
	if not current then
		current = rewards.normalize_table(
			core.deserialize(mod_storage:get_string(STORAGE_KEY)), config.is_item)
	end
	return current
end

--- Returns a copy of the table: one { name, count } per occasion, and
-- daily_limit.
function config.table()
	return rewards.check_table(get(), function() return true end)
end

--- Sets the table. It is taken as a whole or not at all.
-- @return true  or  false, what is wrong: the name of an occasion or
--   "daily_limit"
function config.set(candidate)
	local clean, why = rewards.check_table(candidate, config.is_item)
	if not clean then
		return false, why
	end
	current = clean
	mod_storage:set_string(STORAGE_KEY, core.serialize(clean))
	return true
end

--- Puts the default back.
function config.reset()
	current = rewards.default_table()
	mod_storage:set_string(STORAGE_KEY, "")
end

--- Returns what is paid for an occasion as a list of { name, count }.
-- @param effort Optional, see rewards.FACTOR.
function config.items(occasion, effort)
	return rewards.items(get(), occasion, effort)
end

--- Returns how many daily tasks are rewarded per player and day.
function config.daily_limit()
	return get().daily_limit
end

return config
