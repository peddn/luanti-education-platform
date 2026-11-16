-- Where the trophies of a player are kept: what they earned, what stands
-- on which pedestal, and the counters. Only this file knows the storage,
-- so it can be replaced when the backend becomes the source of this data.

local storage = {}

local mod_storage = core.get_mod_storage()

local function key(player_name)
	return "player:" .. player_name
end

--- Returns the stored state of a player, or nil.
function storage.load(player_name)
	return core.deserialize(mod_storage:get_string(key(player_name)))
end

--- Stores the state of a player.
function storage.save(player_name, state)
	mod_storage:set_string(key(player_name), core.serialize(state))
end

--- Returns the names of all players with a stored state, sorted.
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

return storage
