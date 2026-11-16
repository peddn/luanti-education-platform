-- Rules of the rewards. Pure Lua, no engine calls.

local rewards = {}

-- The three sizes of a reward.
rewards.SMALL = "small"
rewards.MEDIUM = "medium"
rewards.LARGE = "large"
rewards.SIZES = { rewards.SMALL, rewards.MEDIUM, rewards.LARGE }

-- Kinds of tasks, as in lep_progress.
rewards.KIND_TASK = "task"
rewards.KIND_DAILY = "daily"

-- Effort of a daily task and the reward size it earns.
rewards.SIZE_FOR_EFFORT = {
	low = rewards.SMALL,
	normal = rewards.MEDIUM,
	high = rewards.LARGE,
}

-- Why a reward was paid, for the protocol.
rewards.REASON_TASK = "task"
rewards.REASON_DAILY = "daily"
rewards.REASON_LEVEL = "level"
rewards.REASON_STAGE = "stage"

-- How many daily tasks are rewarded per day.
rewards.DEFAULT_DAILY_LIMIT = 5

rewards.DEFAULT_ITEMS = {
	small = "default:steel_ingot 1",
	medium = "default:gold_ingot 1",
	large = "default:diamond 1",
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

--- Returns size and reason of the reward for a reported task, or nil if
-- it earns none.
--
-- A level task is not repeatable: it earns the small reward only while it
-- counts for the workload of the player's level. A daily task earns a
-- reward every day, sized by its effort, if it is on the player's level or
-- above. The caller applies the daily limit.
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
		local size = rewards.SIZE_FOR_EFFORT[result.effort] or rewards.MEDIUM
		return size, rewards.REASON_DAILY
	end
	if result.counted ~= true then
		return nil
	end
	return rewards.SMALL, rewards.REASON_TASK
end

--- Returns size and reason of the reward for a completed level. Only the
-- end of a stage earns the large one.
function rewards.for_level(is_stage)
	if is_stage then
		return rewards.LARGE, rewards.REASON_STAGE
	end
	return rewards.MEDIUM, rewards.REASON_LEVEL
end

--- Reads a list of items like "default:steel_ingot 1, default:coal_lump 3".
-- @return list of { name = ..., count = ... }  or  nil, error message
function rewards.parse_items(text)
	if type(text) ~= "string" then
		return nil, "items must be text"
	end
	local items = {}
	for part in (text .. ","):gmatch("(.-),") do
		part = part:match("^%s*(.-)%s*$")
		if part ~= "" then
			local name, count = part:match("^([%w_]+:[%w_]+)%s*(%d*)$")
			if not name then
				return nil, "cannot read item '" .. part .. "'"
			end
			count = count == "" and 1 or tonumber(count)
			if count < 1 then
				return nil, "count of '" .. name .. "' must be at least 1"
			end
			items[#items + 1] = { name = name, count = count }
		end
	end
	if #items == 0 then
		return nil, "no items given"
	end
	return items
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
