-- Where progress is kept. Only this file knows the storage, so it can be
-- replaced when the backend becomes the source of this data.
--
-- Data is stored by account name, so it can be read and changed while the
-- player is offline.

local storage = {}

local mod_storage = core.get_mod_storage()

local function key(player_name)
	return "player:" .. player_name
end

--- Returns the stored states of a player as { [module_id] = state }.
function storage.load(player_name)
	local data = core.deserialize(mod_storage:get_string(key(player_name)))
	if type(data) ~= "table" then
		return {}
	end
	return data
end

--- Stores the state of a player in one module.
function storage.save(player_name, module_id, state)
	local data = storage.load(player_name)
	data[module_id] = state
	mod_storage:set_string(key(player_name), core.serialize(data))
end

--- Returns the names of all players with stored progress, sorted.
function storage.players()
	local names = {}
	for _, stored_key in ipairs(mod_storage:get_keys()) do
		local name = stored_key:match("^player:(.+)$")
		if name then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	return names
end

--- Deletes everything stored about a player.
function storage.remove(player_name)
	mod_storage:set_string(key(player_name), "")
end

return storage
