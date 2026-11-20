-- Rules of the rewards. Pure Lua, no engine calls.

local rewards = {}

-- What a reward is paid for. The table of a world says per occasion
-- which item and how many.
rewards.TASK = "task"      -- a solved level task
rewards.DAILY = "daily"    -- a solved daily task
rewards.LEVEL = "level"    -- a completed level
rewards.STAGE = "stage"    -- a completed stage
rewards.MODULE = "module"  -- a completed module
rewards.OCCASIONS = {
	rewards.TASK, rewards.DAILY, rewards.LEVEL, rewards.STAGE, rewards.MODULE,
}

-- Kinds of tasks, as in lep_progress.
rewards.KIND_TASK = "task"
rewards.KIND_DAILY = "daily"

-- How hard something was, as in lep_progress, and how often the count
-- of the table is paid for it. Modules differ in how hard they are; the
-- table is the same for all of them.
rewards.EFFORT_LOW = "low"
rewards.EFFORT_NORMAL = "normal"
rewards.EFFORT_HIGH = "high"
rewards.FACTOR = { low = 1, normal = 2, high = 3 }

-- Why a reward was paid, for the protocol.
rewards.REASON_TASK = "task"
rewards.REASON_DAILY = "daily"
rewards.REASON_LEVEL = "level"
rewards.REASON_STAGE = "stage"
rewards.REASON_MODULE = "module"

-- The items a teacher may choose from unless the admin sets another
-- list. Items a world does not have are left out there.
rewards.DEFAULT_CHOICES = "default:coal_lump,default:steel_ingot,default:copper_ingot,"
	.. "default:tin_ingot,default:bronze_ingot,default:gold_ingot,default:mese_crystal,"
	.. "default:diamond,default:apple,farming:bread,default:torch,default:book"

--- Reads a list of item names like "default:diamond, farming:bread".
-- @return List of names without duplicates, in the order given. What is
--   no item name is left out.
function rewards.parse_choices(text)
	local list, seen = {}, {}
	for part in tostring(text or ""):gmatch("[^,]+") do
		local name = part:match("^%s*([%w_]+:[%w_]+)%s*$")
		if name and not seen[name] then
			seen[name] = true
			list[#list + 1] = name
		end
	end
	return list
end

-- Limits of what a table may hold.
rewards.MAX_COUNT = 99
rewards.MAX_DAILY_LIMIT = 20

-- The table of a world nobody has changed: one item with a count per
-- occasion, and how many daily tasks are rewarded per player and day.
rewards.DEFAULT_TABLE = {
	task = { name = "default:steel_ingot", count = 1 },
	daily = { name = "default:gold_ingot", count = 1 },
	level = { name = "default:gold_ingot", count = 1 },
	stage = { name = "default:diamond", count = 1 },
	module = { name = "default:diamond", count = 3 },
	daily_limit = 5,
}

-- Where a reward is put.
rewards.TO_INVENTORY = "inventory"
rewards.TO_CHEST = "chest"

--- Returns where a reward goes first.
--
-- The reward of a daily task goes straight into the inventory if the
-- player carries the survival inventory at that moment, for example at a
-- task chest in the wilderness. Everything else goes into the reward
-- chest: rewards earned in a learning room, where the survival inventory
-- is stored away, and the rewards for level tasks and completed levels.
-- What does not fit into the inventory goes into the chest as well.
-- @param reason One of the REASON_ constants.
-- @param carries_survival True if the player is online and carries the
--   survival inventory.
function rewards.destination(reason, carries_survival)
	if reason == rewards.REASON_DAILY and carries_survival == true then
		return rewards.TO_INVENTORY
	end
	return rewards.TO_CHEST
end

--- Returns occasion, reason and effort of the reward for a reported
-- task, or nil if it earns none.
--
-- A level task is not repeatable: it earns a reward only while it counts
-- for the workload of the player's level. A daily task earns a reward
-- every day if it is on the player's level or above. The caller applies
-- the daily limit. How hard the task was multiplies the count.
-- @param result Table with solved, level, player_level, kind, counted and
--   effort.
function rewards.for_result(result)
	if result.solved ~= true then
		return nil
	end
	if result.kind == rewards.KIND_DAILY then
		if result.level < result.player_level then
			return nil
		end
		local effort = rewards.FACTOR[result.effort] and result.effort or rewards.EFFORT_NORMAL
		return rewards.DAILY, rewards.REASON_DAILY, effort
	end
	if result.counted ~= true then
		return nil
	end
	local effort = rewards.FACTOR[result.effort] and result.effort or rewards.EFFORT_LOW
	return rewards.TASK, rewards.REASON_TASK, effort
end

--- Returns occasion and reason of the reward for a completed level.
-- There is exactly one, the highest that fits: the last level completes
-- the module, a level that ends a stage earns the one of the stage.
function rewards.for_level(is_stage, is_last)
	if is_last then
		return rewards.MODULE, rewards.REASON_MODULE
	elseif is_stage then
		return rewards.STAGE, rewards.REASON_STAGE
	end
	return rewards.LEVEL, rewards.REASON_LEVEL
end

--- Returns what is paid for an occasion as a list of { name, count }, or
-- nil for an unknown occasion.
-- @param effort One of the EFFORT_ constants; low if it is none of them.
function rewards.items(table_, occasion, effort)
	local row = table_[occasion]
	if type(row) ~= "table" then
		return nil
	end
	return { { name = row.name, count = row.count * (rewards.FACTOR[effort] or 1) } }
end

local function whole(value, min, max)
	return type(value) == "number" and value == math.floor(value)
		and value >= min and value <= max
end

--- Checks a table somebody wants to set and returns a clean copy.
-- @param is_item Function(name) returning true for an item that may be
--   given out.
-- @return table  or  nil, what is wrong: the name of the occasion or
--   "daily_limit"
function rewards.check_table(candidate, is_item)
	if type(candidate) ~= "table" then
		return nil, "table"
	end
	local clean = {}
	for _, occasion in ipairs(rewards.OCCASIONS) do
		local row = candidate[occasion]
		if type(row) ~= "table" or type(row.name) ~= "string"
				or not row.name:match("^[%w_]+:[%w_]+$") or not is_item(row.name)
				or not whole(row.count, 1, rewards.MAX_COUNT) then
			return nil, occasion
		end
		clean[occasion] = { name = row.name, count = row.count }
	end
	if not whole(candidate.daily_limit, 0, rewards.MAX_DAILY_LIMIT) then
		return nil, "daily_limit"
	end
	clean.daily_limit = candidate.daily_limit
	return clean
end

--- Returns a copy of the default table.
function rewards.default_table()
	local copy = { daily_limit = rewards.DEFAULT_TABLE.daily_limit }
	for _, occasion in ipairs(rewards.OCCASIONS) do
		local row = rewards.DEFAULT_TABLE[occasion]
		copy[occasion] = { name = row.name, count = row.count }
	end
	return copy
end

--- Repairs a table that comes from storage: what cannot be used is
-- taken from the default, row by row.
function rewards.normalize_table(stored, is_item)
	local result = rewards.default_table()
	if type(stored) ~= "table" then
		return result
	end
	for _, occasion in ipairs(rewards.OCCASIONS) do
		local row = stored[occasion]
		if type(row) == "table" and type(row.name) == "string" and is_item(row.name)
				and whole(row.count, 1, rewards.MAX_COUNT) then
			result[occasion] = { name = row.name, count = row.count }
		end
	end
	if whole(stored.daily_limit, 0, rewards.MAX_DAILY_LIMIT) then
		result.daily_limit = stored.daily_limit
	end
	return result
end

--- Returns the daily allowance of a player who has not earned anything:
-- the day and the number of rewarded daily tasks on that day.
function rewards.new_allowance()
	return { day = "", daily = 0 }
end

--- Repairs an allowance that comes from storage.
function rewards.normalize_allowance(state)
	local result = rewards.new_allowance()
	if type(state) ~= "table" then
		return result
	end
	if type(state.day) == "string" then
		result.day = state.day
	end
	if type(state.daily) == "number" and state.daily > 0 then
		result.daily = math.floor(state.daily)
	end
	return result
end

local function for_today(state, today)
	if state.day == today then
		return { day = today, daily = state.daily }
	end
	return { day = today, daily = 0 }
end

--- Returns how many rewarded daily tasks are left today.
-- @param today Text naming the day, for example "2026-11-16".
function rewards.remaining(state, today, limit)
	return math.max(0, limit - for_today(state, today).daily)
end

--- Uses one rewarded daily task of the allowance.
-- @return new state, true if there was one left, number left afterwards
function rewards.use_allowance(state, today, limit)
	local current = for_today(state, today)
	if current.daily >= limit then
		return current, false, 0
	end
	current.daily = current.daily + 1
	return current, true, limit - current.daily
end

return rewards
