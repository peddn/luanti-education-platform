-- Public API of lep_trophies.

local load = lep_core.loader("lep_trophies")
local trophies = load("src/trophies")
local storage = load("game/storage")
local S = core.get_translator("lep_trophies")

-- Number of pedestals in a personal room.
lep_trophies.SLOTS = 6

lep_trophies.BRONZE = trophies.BRONZE
lep_trophies.SILVER = trophies.SILVER
lep_trophies.GOLD = trophies.GOLD

local registry = trophies.new_registry()

local dispatcher = lep_core.events.new(function(event_name, err)
	core.log("error", "[lep_trophies] callback for " .. event_name .. " failed: "
		.. tostring(err))
end)

--- Returns the state of a player. For the files of this mod only.
function lep_trophies._get_state(player_name)
	return trophies.normalize(storage.load(player_name), lep_trophies.SLOTS)
end

--- Stores the state of a player. For the files of this mod only.
function lep_trophies._set_state(player_name, state)
	storage.save(player_name, state)
end

--- Registers a trophy. Any mod can do this.
-- @param id Unique id, by convention prefixed with the mod name.
-- @param def Table with title, optional description, optional material
--   (lep_trophies.BRONZE, SILVER or GOLD, default bronze) and optional
--   node: the name of a node shown on the pedestal instead of the cup.
function lep_trophies.register_trophy(id, def)
	registry:register(id, def)
end

--- Returns title, description, material and node of a trophy, or nil.
function lep_trophies.get_trophy(id)
	local def = registry:get(id)
	if not def then
		return nil
	end
	return {
		id = def.id, title = def.title, description = def.description,
		material = def.material, node = def.node,
	}
end

--- Returns true if the player has earned the trophy.
function lep_trophies.has(player_name, id)
	return trophies.has(lep_trophies._get_state(player_name), id)
end

--- Returns the ids of the trophies a player has earned, oldest first.
-- Trophies that are no longer registered are left out.
function lep_trophies.get_earned(player_name)
	local list = {}
	for _, id in ipairs(lep_trophies._get_state(player_name).earned) do
		if registry:get(id) then
			list[#list + 1] = id
		end
	end
	return list
end

--- Returns the names of all players who have a stored state, sorted.
-- They do not have to be online.
function lep_trophies.get_players()
	return storage.players()
end

--- Gives a trophy to a player. Nothing happens if they already have it.
-- @return true if the player did not have it yet, false otherwise,
--   or nil and an error message for an unknown trophy
function lep_trophies.award(player_name, id)
	local def = registry:get(id)
	if not def then
		return nil, "unknown trophy '" .. tostring(id) .. "'"
	end
	if type(player_name) ~= "string" or player_name == "" then
		return nil, "player name must be a non-empty string"
	end
	local state, is_new = trophies.award(lep_trophies._get_state(player_name), id)
	if not is_new then
		return false
	end
	storage.save(player_name, state)
	core.log("action", "[lep_trophies] " .. player_name .. " earned " .. id)
	if core.get_player_by_name(player_name) then
		core.chat_send_player(player_name,
			S("New trophy: @1. You can put it on a pedestal in your room.", def.title))
	end
	dispatcher:emit("awarded", player_name, id)
	return true
end

--- Registers a function(player_name, trophy_id) called when a player
-- earns a trophy.
lep_trophies.register_on_awarded = dispatcher:registrar("awarded")

-- An account that is removed takes its trophies along. The pedestals
-- stand in its room, which the lobby empties.
lep_core.register_on_forget_account(storage.remove)
