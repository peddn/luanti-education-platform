-- Public API of lep_places and the code that executes planned steps.

local load = lep_core.loader("lep_places")
local places = load("src/places")
local storage = load("game/storage")

local WILDERNESS = "lep_places:wilderness"

local registry = places.new_registry()
local dispatcher = lep_core.events.new(function(event_name, err)
	core.log("error", "[lep_places] callback for '" .. event_name
		.. "' failed: " .. tostring(err))
end)

-- The wilderness is the survival world itself. Leaving it remembers the
-- position, so coming back returns to the same spot.
registry:register(WILDERNESS, { remember_position = true })

lep_places.WILDERNESS = WILDERNESS
lep_places.INVENTORY_SURVIVAL = places.INVENTORY_SURVIVAL
lep_places.INVENTORY_LEARNING = places.INVENTORY_LEARNING

-- ---------------------------------------------------------------------------
-- Executing steps
-- ---------------------------------------------------------------------------

local function change_privileges(name, privileges, value)
	local privs = core.get_player_privs(name)
	for _, priv in ipairs(privileges) do
		privs[priv] = value or nil
	end
	core.set_player_privs(name, privs)
end

local step_handlers = {
	store_survival = function(player)
		storage.store_survival(player)
	end,
	clear_inventory = function(player)
		storage.clear_inventory(player)
	end,
	restore_survival = function(player)
		storage.restore_survival(player)
	end,
	grant = function(player, step)
		change_privileges(player:get_player_name(), step.privileges, true)
	end,
	revoke = function(player, step)
		change_privileges(player:get_player_name(), step.privileges, false)
	end,
	teleport = function(player, step)
		player:set_pos(step.pos)
	end,
}

local function execute(player, steps)
	for _, step in ipairs(steps) do
		step_handlers[step.op](player, step)
	end
end

local function read_state(player)
	return places.normalize_state(storage.read_state(player), WILDERNESS)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Registers a place type. See src/places.lua for the definition fields.
function lep_places.register_place(id, def)
	registry:register(id, def)
end

--- Returns true if a place type with this id exists.
function lep_places.is_registered(id)
	return registry:get(id) ~= nil
end

--- Returns the id of the place a player is in, or nil if the player is
-- not online.
function lep_places.get_place(player_name)
	local player = core.get_player_by_name(player_name)
	if not player then
		return nil
	end
	return read_state(player).place
end

--- Moves an online player to a place. This is the only supported way to
-- change a player's place.
-- @param player_name Name of the player.
-- @param place_id Id of the target place.
-- @param pos Optional target position. Without it the remembered or
--        default position of the place is used.
-- @return true  or  false, error message
function lep_places.move(player_name, place_id, pos)
	local player = core.get_player_by_name(player_name)
	if not player then
		return false, "player '" .. tostring(player_name) .. "' is not online"
	end

	local state = read_state(player)
	local steps, new_state = places.plan_move(registry, state, {
		target = place_id,
		pos = pos,
		current_pos = player:get_pos(),
		current_privs = core.get_player_privs(player_name),
	})
	if not steps then
		return false, new_state
	end

	execute(player, steps)
	storage.write_state(player, new_state)

	core.log("action", "[lep_places] " .. player_name .. " moved from "
		.. state.place .. " to " .. new_state.place)
	dispatcher:emit("place_changed", player_name, state.place, new_state.place)
	return true
end

--- Registers a function(player_name, old_place, new_place) that is called
-- after a player has been moved.
lep_places.register_on_place_changed = dispatcher:registrar("place_changed")

-- ---------------------------------------------------------------------------
-- Keeping the state consistent
-- ---------------------------------------------------------------------------

-- Privileges are stored permanently by the engine. After a crash a player
-- could keep a privilege of a place they are no longer in, so the state is
-- repaired on every join.
core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	local state = read_state(player)
	local steps, new_state = places.plan_join(registry, state, WILDERNESS,
		core.get_player_privs(name))

	if #steps > 0 then
		core.log("action", "[lep_places] repairing state of " .. name
			.. " on join (" .. #steps .. " steps)")
	end
	execute(player, steps)
	storage.write_state(player, new_state)
end)
