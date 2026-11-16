-- Where the rewards of a player are kept: the daily allowance, the
-- content of the reward chest and the rewards waiting for room in it.
-- Stored by account name, so rewards arrive while the player is offline.

local storage = {}

local mod_storage = core.get_mod_storage()

local function key(player_name)
	return "player:" .. player_name
end

--- Returns the stored data of a player: allowance, chest, pending.
function storage.load(player_name)
	local data = core.deserialize(mod_storage:get_string(key(player_name)))
	if type(data) ~= "table" then
		data = {}
	end
	if type(data.chest) ~= "table" then
		data.chest = {}
	end
	if type(data.pending) ~= "table" then
		data.pending = {}
	end
	return data
end

--- Stores the data of a player.
function storage.save(player_name, data)
	mod_storage:set_string(key(player_name), core.serialize(data))
end

return storage
