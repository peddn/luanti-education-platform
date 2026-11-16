-- Place registry and transition planning. Pure Lua, no engine calls.
--
-- A place type describes where a player can be (wilderness, lobby, a
-- learning room) and which inventory and privileges apply there.
-- planning turns "player is in A, wants to go to B" into a list of steps
-- that the game layer executes.

local places = {}

places.INVENTORY_SURVIVAL = "survival"
places.INVENTORY_LEARNING = "learning"

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function copy_pos(pos)
	return { x = pos.x, y = pos.y, z = pos.z }
end

local function is_pos(pos)
	return type(pos) == "table"
		and type(pos.x) == "number"
		and type(pos.y) == "number"
		and type(pos.z) == "number"
end

local function copy_set(set)
	local result = {}
	for key, value in pairs(set or {}) do
		if value then
			result[key] = true
		end
	end
	return result
end

local function sorted_keys(set)
	local keys = {}
	for key in pairs(set) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	return keys
end

local function copy_positions(positions)
	local result = {}
	for id, pos in pairs(positions or {}) do
		if is_pos(pos) then
			result[id] = copy_pos(pos)
		end
	end
	return result
end

-- ---------------------------------------------------------------------------
-- Registry
-- ---------------------------------------------------------------------------

local Registry = {}
Registry.__index = Registry

--- Creates an empty registry of place types.
function places.new_registry()
	return setmetatable({ _defs = {} }, Registry)
end

--- Registers a place type.
-- @param id Unique id, e.g. "lep_places:wilderness".
-- @param def Table with:
--   inventory          "survival" (default) or "learning"
--   privileges         set of privileges granted while in this place,
--                      e.g. { fly = true }
--   remember_position  if true, the position is saved when leaving and
--                      used when entering without an explicit position
--   default_pos        position used when entering without an explicit
--                      or remembered position
--   title              optional name of the place for people, for example
--                      in the overview of the teacher's desk
function Registry:register(id, def)
	assert(type(id) == "string" and id ~= "",
		"register: id must be a non-empty string")
	assert(type(def) == "table", "register: def must be a table")
	assert(not self._defs[id], "register: place '" .. id .. "' already exists")

	local inventory = def.inventory or places.INVENTORY_SURVIVAL
	assert(inventory == places.INVENTORY_SURVIVAL
		or inventory == places.INVENTORY_LEARNING,
		"register: inventory must be 'survival' or 'learning'")
	assert(def.default_pos == nil or is_pos(def.default_pos),
		"register: default_pos must be a position")
	assert(def.title == nil or (type(def.title) == "string" and def.title ~= ""),
		"register: title must be a non-empty string")

	self._defs[id] = {
		id = id,
		inventory = inventory,
		privileges = copy_set(def.privileges),
		remember_position = def.remember_position == true,
		default_pos = def.default_pos and copy_pos(def.default_pos) or nil,
		title = def.title,
	}
end

--- Returns the definition of a place type or nil.
function Registry:get(id)
	return self._defs[id]
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

--- Returns the state of a player who has never been moved.
-- @param start_place Id of the place every new player starts in.
function places.initial_state(start_place)
	assert(type(start_place) == "string" and start_place ~= "",
		"initial_state: start_place must be a non-empty string")
	return {
		place = start_place,
		previous = nil,
		positions = {},
		granted = {},
		survival_stored = false,
	}
end

--- Returns a cleaned copy of a state loaded from storage.
-- Unknown or broken fields are replaced by safe defaults.
function places.normalize_state(state, start_place)
	local result = places.initial_state(start_place)
	if type(state) ~= "table" then
		return result
	end
	if type(state.place) == "string" and state.place ~= "" then
		result.place = state.place
	end
	if type(state.positions) == "table" then
		result.positions = copy_positions(state.positions)
	end
	if type(state.granted) == "table" then
		result.granted = copy_set(state.granted)
	end
	result.survival_stored = state.survival_stored == true
	if type(state.previous) == "string" and state.previous ~= "" then
		result.previous = state.previous
	end
	return result
end

-- ---------------------------------------------------------------------------
-- Planning
-- ---------------------------------------------------------------------------

-- Adds the steps that bring privileges in line with the target place.
-- Only privileges that were granted by this system are ever revoked.
local function plan_privileges(steps, granted, wanted, current_privs)
	local new_granted = {}
	local revoke, grant = {}, {}

	for priv in pairs(granted) do
		if wanted[priv] then
			new_granted[priv] = true
			-- Still wanted. Re-grant if it got lost, e.g. revoked by hand.
			if not current_privs[priv] then
				grant[priv] = true
			end
		else
			revoke[priv] = true
		end
	end

	for priv in pairs(wanted) do
		if not granted[priv] and not current_privs[priv] then
			grant[priv] = true
			new_granted[priv] = true
		end
	end

	if next(revoke) then
		steps[#steps + 1] = { op = "revoke", privileges = sorted_keys(revoke) }
	end
	if next(grant) then
		steps[#steps + 1] = { op = "grant", privileges = sorted_keys(grant) }
	end
	return new_granted
end

--- Plans moving a player to another place.
-- @param registry Registry of place types.
-- @param state Current state of the player.
-- @param request Table with:
--   target         id of the target place
--   pos            optional explicit target position
--   current_pos    current position of the player
--   current_privs  set of privileges the player has right now
-- @return steps, new_state  or  nil, error message
function places.plan_move(registry, state, request)
	assert(type(state) == "table", "plan_move: state must be a table")
	assert(type(request) == "table", "plan_move: request must be a table")

	local target = registry:get(request.target)
	if not target then
		return nil, "unknown place '" .. tostring(request.target) .. "'"
	end
	if request.pos ~= nil and not is_pos(request.pos) then
		return nil, "invalid target position"
	end
	if not is_pos(request.current_pos) then
		return nil, "invalid current position"
	end

	local source = registry:get(state.place)
	local positions = copy_positions(state.positions)
	local steps = {}

	-- 1. Remember where the player was, if the place asks for it.
	-- Moving within the same place keeps the remembered position.
	if source and source.remember_position and source.id ~= target.id then
		positions[source.id] = copy_pos(request.current_pos)
	end

	-- Remember where the player came from, so they can be sent back.
	-- Learning rooms do not count: leaving a chain of rooms leads back to
	-- the lobby or the wilderness, not to the room before.
	local previous = state.previous
	if source and source.id ~= target.id
			and source.inventory == places.INVENTORY_SURVIVAL then
		previous = source.id
	end

	-- 2. Find the target position.
	local target_pos = request.pos
		or (target.id ~= state.place and positions[target.id])
		or target.default_pos
	if not target_pos then
		return nil, "no position known for place '" .. target.id .. "'"
	end
	target_pos = copy_pos(target_pos)

	-- 3. Inventory. The survival inventory is the only one that is kept.
	local survival_stored = state.survival_stored == true
	if target.inventory == places.INVENTORY_LEARNING then
		if not survival_stored then
			steps[#steps + 1] = { op = "store_survival" }
			survival_stored = true
		end
		steps[#steps + 1] = { op = "clear_inventory" }
	else
		if survival_stored then
			steps[#steps + 1] = { op = "clear_inventory" }
			steps[#steps + 1] = { op = "restore_survival" }
			survival_stored = false
		end
	end

	-- 4. Privileges.
	local granted = plan_privileges(steps, copy_set(state.granted),
		target.privileges, request.current_privs or {})

	-- 5. Teleport last, so a failure before leaves the player in place.
	steps[#steps + 1] = { op = "teleport", pos = target_pos }

	return steps, {
		place = target.id,
		previous = previous,
		positions = positions,
		granted = granted,
		survival_stored = survival_stored,
	}
end

--- Plans sending a player back to the place they came from.
-- Falls back to request.fallback if no previous place is known or it can
-- no longer be entered.
-- @param request Table with fallback, current_pos, current_privs.
-- @return steps, new_state  or  nil, error message
function places.plan_back(registry, state, request)
	assert(type(state) == "table", "plan_back: state must be a table")
	assert(type(request) == "table", "plan_back: request must be a table")

	return places.plan_move(registry, state, {
		target = places.back_target(registry, state, request.fallback),
		current_pos = request.current_pos,
		current_privs = request.current_privs,
	})
end

--- Returns the id of the place that going back leads to: the previous
-- place if the player can arrive there, otherwise the fallback.
function places.back_target(registry, state, fallback)
	local previous = registry:get(state.previous)
	if previous and previous.id ~= state.place
			and ((state.positions or {})[previous.id] or previous.default_pos) then
		return previous.id
	end
	return fallback
end

--- Plans the repair of a player's state when they join.
-- Makes privileges match the stored place. If the stored place no longer
-- exists, the player is treated as being in fallback_place, without
-- being teleported.
-- @return steps, new_state
function places.plan_join(registry, state, fallback_place, current_privs)
	assert(type(state) == "table", "plan_join: state must be a table")

	local place = registry:get(state.place)
	local steps = {}
	local survival_stored = state.survival_stored == true

	if not place then
		place = registry:get(fallback_place)
		assert(place, "plan_join: fallback place is not registered")
		if place.inventory == places.INVENTORY_SURVIVAL and survival_stored then
			steps[#steps + 1] = { op = "clear_inventory" }
			steps[#steps + 1] = { op = "restore_survival" }
			survival_stored = false
		end
	end

	local granted = plan_privileges(steps, copy_set(state.granted),
		place.privileges, current_privs or {})

	return steps, {
		place = place.id,
		previous = state.previous,
		positions = copy_positions(state.positions),
		granted = granted,
		survival_stored = survival_stored,
	}
end

return places
