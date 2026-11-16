-- Public API of lep_rewards and the link to lep_progress.

local load = lep_core.loader("lep_rewards")
local rewards = load("src/rewards")
local config = load("game/config")
local storage = load("game/storage")
local inventory = load("game/inventory")
local S = core.get_translator("lep_rewards")

local protocol = lep_core.protocols.open("rewards",
	{ "account", "size", "reason", "module", "level", "task", "items" })

lep_rewards.SMALL = rewards.SMALL
lep_rewards.MEDIUM = rewards.MEDIUM
lep_rewards.LARGE = rewards.LARGE

local function today()
	return os.date("%Y-%m-%d")
end

-- "default:steel_ingot 2" for the protocol.
local function items_as_text(items)
	local parts = {}
	for index, item in ipairs(items) do
		parts[index] = item.name .. " " .. item.count
	end
	return table.concat(parts, ", ")
end

--- Returns the items as text for players, for example "2 x Steel Ingot".
function lep_rewards.describe_items(items)
	local parts = {}
	for index, item in ipairs(items) do
		local def = core.registered_items[item.name]
		local description = def and def.short_description or def and def.description
		parts[index] = item.count .. " x " .. (description or item.name):match("^[^\n]*")
	end
	return table.concat(parts, ", ")
end

--- Returns what a reward size contains, as a list of { name, count }.
-- Learning modules use this to show the reward before the task.
function lep_rewards.get_reward(size)
	local items = config.items(size)
	if not items then
		return nil
	end
	local copy = {}
	for index, item in ipairs(items) do
		copy[index] = { name = item.name, count = item.count }
	end
	return copy
end

--- Returns how many rewarded tasks and task chests a player has left
-- today, as { task = ..., chest = ... }, and the limits in the same form.
function lep_rewards.get_remaining(player_name)
	local allowance = rewards.normalize_allowance(storage.load(player_name).allowance)
	local limits = config.limits()
	return rewards.remaining(allowance, today(), limits),
		{ task = limits.task, chest = limits.chest }
end

--- Gives a player the full daily allowance back, as at the start of a
-- new day. Rewards already paid stay where they are.
function lep_rewards.reset_allowance(player_name)
	local data = storage.load(player_name)
	data.allowance = rewards.new_allowance()
	storage.save(player_name, data)
	core.log("action", "[lep_rewards] daily allowance of " .. player_name .. " was reset")
end

--- Returns the last entries of the reward protocol of a player, oldest
-- first. Each has time, size, reason, module, level, task and items.
function lep_rewards.get_log(player_name, limit)
	return protocol:read(function(record)
		return record.account == player_name
	end, limit)
end

--- Pays a reward into the chest of a player and writes it down.
-- @param details Optional table with reason, module, level and task.
function lep_rewards.give(player_name, size, details)
	local items = config.items(size)
	assert(items, "lep_rewards.give: unknown size '" .. tostring(size) .. "'")
	details = details or {}

	inventory.add(player_name, items)
	protocol:append({
		account = player_name,
		size = size,
		reason = details.reason,
		module = details.module,
		level = details.level,
		task = details.task,
		items = items_as_text(items),
	})
	core.log("action", "[lep_rewards] " .. player_name .. " received the " .. size
		.. " reward (" .. tostring(details.reason) .. ")")

	if core.get_player_by_name(player_name) then
		core.chat_send_player(player_name, S("Reward: @1. It is in the chest in your room.",
			lep_rewards.describe_items(items)))
	end
end

-- Solved tasks, within the daily limit.
lep_progress.register_on_result(function(result)
	local size, reason = rewards.for_result(result)
	if not size then
		return
	end

	local data = storage.load(result.player)
	local allowance, allowed, left = rewards.use_allowance(
		rewards.normalize_allowance(data.allowance), today(), result.kind, config.limits())
	if not allowed then
		return
	end
	data.allowance = allowance
	storage.save(result.player, data)

	lep_rewards.give(result.player, size, {
		reason = reason,
		module = result.module,
		level = result.level,
		task = result.task,
	})

	if left == 0 and core.get_player_by_name(result.player) then
		if result.kind == rewards.KIND_CHEST then
			core.chat_send_player(result.player,
				S("That was the last rewarded task chest for today."))
		else
			core.chat_send_player(result.player,
				S("That was the last rewarded task for today."))
		end
	end
end)

-- Completed levels. They do not count towards the daily limit.
lep_progress.register_on_level_completed(function(player_name, module_id, level, is_stage)
	local size, reason = rewards.for_level(is_stage)
	lep_rewards.give(player_name, size, {
		reason = reason,
		module = module_id,
		level = level,
	})
end)
