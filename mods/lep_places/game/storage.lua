-- Reads and writes the place state and the stored survival inventory
-- of a player. Everything lives in the player's metadata.

local storage = {}

local STATE_KEY = "lep_places:state"
local SURVIVAL_KEY = "lep_places:survival"
local RETURNS_KEY = "lep_places:returns"
-- Key in the storage of the mod: privileges of the place, by player name.
local GRANTED_PREFIX = "granted:"

local mod_storage = core.get_mod_storage()

-- Inventory lists that make up the survival inventory.
local SURVIVAL_LISTS = { "main", "craft" }

--- Returns the stored state table or nil.
function storage.read_state(player)
	local raw = player:get_meta():get_string(STATE_KEY)
	if raw == "" then
		return nil
	end
	return core.parse_json(raw)
end

function storage.write_state(player, state)
	player:get_meta():set_string(STATE_KEY, core.write_json(state))
	-- The privileges of the place are also kept by name, so they can be
	-- asked for while the player is away. See storage.read_granted.
	local granted = {}
	for privilege in pairs(type(state.granted) == "table" and state.granted or {}) do
		granted[#granted + 1] = privilege
	end
	table.sort(granted)
	mod_storage:set_string(GRANTED_PREFIX .. player:get_player_name(),
		table.concat(granted, ","))
end

--- Returns the set of privileges a player holds only because of the
-- place they were in when their state was written last. Works for
-- players who are away.
function storage.read_granted(player_name)
	local set = {}
	for privilege in mod_storage:get_string(GRANTED_PREFIX .. player_name):gmatch("[^,]+") do
		set[privilege] = true
	end
	return set
end

--- Returns the stored return positions: a table from place id to
-- position, see lep_places.set_return.
function storage.read_returns(player)
	local data = core.parse_json(player:get_meta():get_string(RETURNS_KEY), nil, true)
	return type(data) == "table" and data or {}
end

function storage.write_returns(player, returns)
	player:get_meta():set_string(RETURNS_KEY,
		next(returns) and core.write_json(returns) or "")
end

--- Saves the survival inventory lists into the player's metadata.
function storage.store_survival(player)
	local inv = player:get_inventory()
	local data = {}
	for _, listname in ipairs(SURVIVAL_LISTS) do
		local stacks = {}
		for i, stack in ipairs(inv:get_list(listname) or {}) do
			stacks[i] = stack:to_string()
		end
		data[listname] = stacks
	end
	player:get_meta():set_string(SURVIVAL_KEY, core.write_json(data))
end

--- Empties the survival inventory lists.
function storage.clear_inventory(player)
	local inv = player:get_inventory()
	for _, listname in ipairs(SURVIVAL_LISTS) do
		local size = inv:get_size(listname)
		local empty = {}
		for i = 1, size do
			empty[i] = ""
		end
		inv:set_list(listname, empty)
	end
end

--- Puts the saved survival inventory back and removes the saved copy.
-- @return true if a saved inventory was found.
function storage.restore_survival(player)
	local meta = player:get_meta()
	local raw = meta:get_string(SURVIVAL_KEY)
	if raw == "" then
		return false
	end
	local data = core.parse_json(raw)
	if type(data) ~= "table" then
		return false
	end

	local inv = player:get_inventory()
	for _, listname in ipairs(SURVIVAL_LISTS) do
		local stacks = data[listname]
		if type(stacks) == "table" then
			local size = inv:get_size(listname)
			local list = {}
			for i = 1, size do
				list[i] = stacks[i] or ""
			end
			inv:set_list(listname, list)
		end
	end
	meta:set_string(SURVIVAL_KEY, "")
	return true
end

return storage
