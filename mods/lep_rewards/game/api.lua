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

--- Returns how many rewarded daily tasks a player has left today, and
-- the limit per day.
function lep_rewards.get_remaining(player_name)
	local allowance = rewards.normalize_allowance(storage.load(player_name).allowance)
	local limit = config.daily_limit()
	return rewards.remaining(allowance, today(), limit), limit
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

-- Puts items into the main inventory of an online player and returns
-- what did not fit, as a list of { name, count }.
local function add_to_inventory(player_name, items)
	local inv = core.get_player_by_name(player_name):get_inventory()
	local leftovers = {}
	for _, item in ipairs(items) do
		local leftover = inv:add_item("main", ItemStack(item))
		if not leftover:is_empty() then
			leftovers[#leftovers + 1] = { name = leftover:get_name(),
				count = leftover:get_count() }
		end
	end
	return leftovers
end

--- Pays a reward to a player and writes it down. Where it goes is
-- decided by rewards.destination: the reward of a daily task goes into
-- the inventory of a player in survival, everything else and whatever
-- does not fit into the reward chest.
-- @param details Optional table with reason, module, level and task.
function lep_rewards.give(player_name, size, details)
	local items = config.items(size)
	assert(items, "lep_rewards.give: unknown size '" .. tostring(size) .. "'")
	details = details or {}

	local destination = rewards.destination(details.reason,
		lep_places.has_survival_inventory(player_name))
	local for_chest = items
	if destination == rewards.TO_INVENTORY then
		for_chest = add_to_inventory(player_name, items)
	end
	if #for_chest > 0 then
		inventory.add(player_name, for_chest)
	end

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

	if not core.get_player_by_name(player_name) then
		return
	end
	local text = lep_rewards.describe_items(items)
	if destination == rewards.TO_CHEST then
		core.chat_send_player(player_name,
			S("Reward: @1. It is in the chest in your room.", text))
	elseif #for_chest == 0 then
		core.chat_send_player(player_name, S("Reward: @1. It is in your inventory.", text))
	else
		core.chat_send_player(player_name, S("Reward: @1.", text) .. " "
			.. S("Your inventory is full. In the chest in your room: @1",
				lep_rewards.describe_items(for_chest)))
	end
end

-- Solved tasks. Level tasks are rewarded while they count for the
-- workload, daily tasks within the daily limit.
lep_progress.register_on_result(function(result)
	local size, reason = rewards.for_result(result)
	if not size then
		return
	end

	local last_today = false
	if result.kind == rewards.KIND_DAILY then
		local data = storage.load(result.player)
		local allowance, allowed, left = rewards.use_allowance(
			rewards.normalize_allowance(data.allowance), today(), config.daily_limit())
		if not allowed then
			return
		end
		data.allowance = allowance
		storage.save(result.player, data)
		last_today = left == 0
	end

	lep_rewards.give(result.player, size, {
		reason = reason,
		module = result.module,
		level = result.level,
		task = result.task,
	})

	if last_today and core.get_player_by_name(result.player) then
		core.chat_send_player(result.player,
			S("That was the last rewarded daily task for today."))
	end
end)

-- Tell learning modules what a task will earn, so they can show it.
lep_progress.register_task_info(function(player_name, module_id, level, task_id, kind)
	local info = lep_progress.get_progress(player_name, module_id)
	if not info then
		return nil
	end
	local counted = false
	if kind ~= rewards.KIND_DAILY and level == info.level then
		for _, task in ipairs(info.tasks) do
			if task.id == task_id then
				counted = task.solved < task.required
			end
		end
	end
	local size = rewards.for_result({
		solved = true, level = level, player_level = info.level, kind = kind,
		counted = counted, effort = "normal",
	})
	if not size then
		return S("No reward: you have finished this kind of task.")
	end
	if kind == rewards.KIND_DAILY and lep_rewards.get_remaining(player_name) == 0 then
		return S("No reward: the daily limit is reached.")
	end
	return S("Reward: @1", lep_rewards.describe_items(config.items(size)))
end)

-- Completed levels.
lep_progress.register_on_level_completed(function(player_name, module_id, level, is_stage)
	local size, reason = rewards.for_level(is_stage)
	lep_rewards.give(player_name, size, {
		reason = reason,
		module = module_id,
		level = level,
	})
end)
