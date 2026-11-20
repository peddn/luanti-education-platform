-- Public API of lep_rewards and the link to lep_progress.

local load = lep_core.loader("lep_rewards")
local rewards = load("src/rewards")
local config = load("game/config")
local storage = load("game/storage")
local inventory = load("game/inventory")
local S = core.get_translator("lep_rewards")

-- The second column held the size of the reward once. Now it says how
-- hard the task or the module was, which multiplies the count.
local protocol = lep_core.protocols.open("rewards",
	{ "account", "effort", "reason", "module", "level", "task", "items" })

local dispatcher = lep_core.events.new(function(event_name, err)
	core.log("error", "[lep_rewards] callback for " .. event_name .. " failed: "
		.. tostring(err))
end)

lep_rewards.TASK = rewards.TASK
lep_rewards.DAILY = rewards.DAILY
lep_rewards.LEVEL = rewards.LEVEL
lep_rewards.STAGE = rewards.STAGE
lep_rewards.MODULE = rewards.MODULE
lep_rewards.OCCASIONS = rewards.OCCASIONS
lep_rewards.MAX_COUNT = rewards.MAX_COUNT
lep_rewards.MAX_DAILY_LIMIT = rewards.MAX_DAILY_LIMIT

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

--- Returns what is paid for an occasion, as a list of { name, count },
-- or nil for an unknown occasion.
-- @param occasion One of lep_rewards.OCCASIONS.
-- @param effort Optional: "low", "normal" or "high". It multiplies the
--   count by one, two or three.
function lep_rewards.get_reward(occasion, effort)
	return config.items(occasion, effort)
end

--- Returns the reward table of this world: one { name, count } for each
-- of lep_rewards.OCCASIONS, and daily_limit.
function lep_rewards.get_table()
	return config.table()
end

--- Returns the items a teacher may choose from, as a list of
-- { name, title }. The title is the name of the item for people.
function lep_rewards.get_choices()
	local list = {}
	for index, name in ipairs(config.choices()) do
		local description = core.registered_items[name].short_description
			or core.registered_items[name].description or name
		list[index] = { name = name, title = description:match("^[^\n]*") }
	end
	return list
end

--- Sets the reward table of this world. It counts from the next reward
-- on; what lies in a chest stays. The table is taken as a whole or not
-- at all, and only with items of lep_rewards.get_choices.
-- @return true  or  false, what is wrong: the name of an occasion or
--   "daily_limit"
function lep_rewards.set_table(candidate)
	local ok, why = config.set(candidate)
	if not ok then
		return false, why
	end
	core.log("action", "[lep_rewards] the reward table was changed")
	dispatcher:emit("table_changed")
	return true
end

--- Puts the default table back.
function lep_rewards.reset_table()
	config.reset()
	core.log("action", "[lep_rewards] the reward table was reset to the default")
	dispatcher:emit("table_changed")
end

--- Registers a function() called after the reward table was changed.
lep_rewards.register_on_table_changed = dispatcher:registrar("table_changed")

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
-- @param occasion One of lep_rewards.OCCASIONS.
-- @param details Optional table with reason, effort, module, level and
--   task.
function lep_rewards.give(player_name, occasion, details)
	details = details or {}
	local items = config.items(occasion, details.effort)
	assert(items, "lep_rewards.give: unknown occasion '" .. tostring(occasion) .. "'")

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
		effort = details.effort,
		reason = details.reason,
		module = details.module,
		level = details.level,
		task = details.task,
		items = items_as_text(items),
	})
	core.log("action", "[lep_rewards] " .. player_name .. " received the reward for a "
		.. occasion .. " (" .. tostring(details.reason) .. ")")

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
	local occasion, reason, effort = rewards.for_result(result)
	if not occasion then
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

	lep_rewards.give(result.player, occasion, {
		reason = reason,
		effort = effort,
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
	-- A level task is as hard as its module. Of a daily task the effort
	-- is only known when it is reported; normal is the usual one.
	local module = lep_progress.get_module(module_id)
	local occasion, _, effort = rewards.for_result({
		solved = true, level = level, player_level = info.level, kind = kind,
		counted = counted,
		effort = kind == rewards.KIND_DAILY and rewards.EFFORT_NORMAL or module.effort,
	})
	if not occasion then
		return S("No reward: you have finished this kind of task.")
	end
	if kind == rewards.KIND_DAILY and lep_rewards.get_remaining(player_name) == 0 then
		return S("No reward: the daily limit is reached.")
	end
	return S("Reward: @1", lep_rewards.describe_items(config.items(occasion, effort)))
end)

-- Completed levels. There is exactly one reward: the last level
-- completes the module and earns the one for that.
lep_progress.register_on_level_completed(function(player_name, module_id, level, is_stage)
	local module = lep_progress.get_module(module_id)
	local occasion, reason = rewards.for_level(is_stage, level == module.levels)
	lep_rewards.give(player_name, occasion, {
		reason = reason,
		effort = module.effort,
		module = module_id,
		level = level,
	})
end)
