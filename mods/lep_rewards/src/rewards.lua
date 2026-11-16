-- Rules of the rewards. Pure Lua, no engine calls.

local rewards = {}

-- The three sizes of a reward.
rewards.SMALL = "small"
rewards.MEDIUM = "medium"
rewards.LARGE = "large"
rewards.SIZES = { rewards.SMALL, rewards.MEDIUM, rewards.LARGE }

-- Where a task came from. Each kind has its own daily limit.
rewards.KIND_TASK = "task"
rewards.KIND_CHEST = "chest"

-- Why a reward was paid, for the protocol.
rewards.REASON_TASK = "task"
rewards.REASON_CHEST = "chest"
rewards.REASON_LEVEL = "level"
rewards.REASON_STAGE = "stage"

rewards.DEFAULT_LIMITS = { task = 10, chest = 5 }

rewards.DEFAULT_ITEMS = {
	small = "default:steel_ingot 1",
	medium = "default:gold_ingot 1",
	large = "default:diamond 1",
}

--- Returns size and reason of the reward for a reported task, or nil if
-- it earns none. Only solved tasks on the player's own level or above
-- are rewarded.
-- @param result Table with solved, level, player_level and kind.
function rewards.for_result(result)
	if result.solved ~= true or result.level < result.player_level then
		return nil
	end
	if result.kind == rewards.KIND_CHEST then
		return rewards.MEDIUM, rewards.REASON_CHEST
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

--- Returns the daily allowance of a player who has not earned anything.
function rewards.new_allowance()
	return { day = "", task = 0, chest = 0 }
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
	for _, kind in ipairs({ rewards.KIND_TASK, rewards.KIND_CHEST }) do
		if type(state[kind]) == "number" and state[kind] > 0 then
			result[kind] = math.floor(state[kind])
		end
	end
	return result
end

local function for_today(state, today)
	if state.day == today then
		return { day = today, task = state.task, chest = state.chest }
	end
	return { day = today, task = 0, chest = 0 }
end

--- Returns how many rewards of each kind are left today.
-- @param today Text naming the day, for example "2026-11-16".
function rewards.remaining(state, today, limits)
	local current = for_today(state, today)
	return {
		task = math.max(0, limits.task - current.task),
		chest = math.max(0, limits.chest - current.chest),
	}
end

--- Uses one reward of the daily allowance.
-- @return new state, true if there was one left, number left afterwards
function rewards.use_allowance(state, today, kind, limits)
	assert(kind == rewards.KIND_TASK or kind == rewards.KIND_CHEST,
		"use_allowance: unknown kind")
	local current = for_today(state, today)
	if current[kind] >= limits[kind] then
		return current, false, 0
	end
	current[kind] = current[kind] + 1
	return current, true, limits[kind] - current[kind]
end

return rewards
