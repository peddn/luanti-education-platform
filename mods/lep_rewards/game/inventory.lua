-- The content of the reward chests. It belongs to the account, not to the
-- chest node, so it survives a rebuild of the lobby and can be filled
-- while the room is not loaded.

local load = lep_core.loader("lep_rewards")
local storage = load("game/storage")

local inventory = {}

inventory.LIST = "main"
inventory.COLUMNS = 8
inventory.ROWS = 2

local SIZE = inventory.COLUMNS * inventory.ROWS
local inventories = {}
local on_refilled = function() end

--- Sets the function(player_name) that is called when waiting rewards
-- moved into the chest because the owner took something out. The chest
-- window uses it to show the new state.
function inventory.set_on_refilled(callback)
	on_refilled = callback
end

--- Returns the name of the detached inventory of a player.
function inventory.location(player_name)
	return "lep_rewards_" .. player_name
end

local function save(player_name, pending)
	local inv = inventories[player_name]
	local data = storage.load(player_name)
	data.chest = {}
	for index, stack in ipairs(inv:get_list(inventory.LIST)) do
		data.chest[index] = stack:to_string()
	end
	if pending then
		data.pending = pending
	end
	storage.save(player_name, data)
end

-- Moves waiting rewards into the chest as far as there is room.
local function refill(player_name)
	local inv = inventories[player_name]
	local pending = {}
	for _, item in ipairs(storage.load(player_name).pending) do
		local leftover = inv:add_item(inventory.LIST, ItemStack(item))
		if not leftover:is_empty() then
			pending[#pending + 1] = leftover:to_string()
		end
	end
	save(player_name, pending)
end

local function get(player_name)
	if inventories[player_name] then
		return inventories[player_name]
	end
	local inv = core.create_detached_inventory(inventory.location(player_name), {
		-- Nothing goes in by hand and nothing is rearranged.
		allow_put = function() return 0 end,
		allow_move = function() return 0 end,
		-- Only the owner takes things out. This is checked here, on the
		-- server, whatever window a client claims to have open.
		allow_take = function(_, _, _, stack, player)
			if player and player:get_player_name() == player_name then
				return stack:get_count()
			end
			return 0
		end,
		on_take = function()
			local had_waiting = #storage.load(player_name).pending > 0
			refill(player_name)
			if had_waiting then
				on_refilled(player_name)
			end
		end,
	}, player_name)
	inv:set_size(inventory.LIST, SIZE)
	local stored = storage.load(player_name).chest
	local list = {}
	for index = 1, SIZE do
		list[index] = ItemStack(stored[index])
	end
	inv:set_list(inventory.LIST, list)
	inventories[player_name] = inv
	return inv
end

--- Makes sure the inventory of a player exists, for the chest window.
function inventory.ensure(player_name)
	get(player_name)
end

--- Puts items into the chest of a player. What does not fit waits and
-- moves in when the player takes something out.
-- @param items List of { name, count }.
function inventory.add(player_name, items)
	get(player_name)
	local data = storage.load(player_name)
	for _, item in ipairs(items) do
		data.pending[#data.pending + 1] = ItemStack(item):to_string()
	end
	storage.save(player_name, data)
	refill(player_name)
end

--- Returns how many stacks are waiting for room in the chest.
function inventory.pending_count(player_name)
	return #storage.load(player_name).pending
end

-- The inventory of a player who left is dropped from memory. Its content
-- is in storage.
core.register_on_leaveplayer(function(player)
	local player_name = player:get_player_name()
	if inventories[player_name] then
		core.remove_detached_inventory(inventory.location(player_name))
		inventories[player_name] = nil
	end
end)

-- An account that is removed takes the content of its chest along, and
-- what was waiting for room in it.
lep_core.register_on_forget_account(function(player_name)
	if inventories[player_name] then
		core.remove_detached_inventory(inventory.location(player_name))
		inventories[player_name] = nil
	end
	storage.remove(player_name)
end)

return inventory
