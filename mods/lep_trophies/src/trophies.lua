-- Trophies and the pedestals they stand on. Pure Lua, no engine calls.
--
-- A trophy is earned once and then belongs to the account. The player
-- decides which of their trophies stand on the pedestals in their room.

local trophies = {}

trophies.BRONZE = "bronze"
trophies.SILVER = "silver"
trophies.GOLD = "gold"

-- How many solved tasks earn a trophy, and in which material.
trophies.TASK_STEPS = {
	{ count = 10, material = trophies.BRONZE },
	{ count = 50, material = trophies.SILVER },
	{ count = 100, material = trophies.GOLD },
}
trophies.DAILY_STEPS = {
	{ count = 10, material = trophies.BRONZE },
	{ count = 50, material = trophies.SILVER },
}

local MATERIALS = { bronze = true, silver = true, gold = true }

--------------------------------------------------------------------------
-- Ids of the trophies this mod creates itself

--- Id of the trophy for completing a stage of a module.
function trophies.stage_id(module_id, level)
	return "lep_trophies:stage:" .. module_id .. ":" .. level
end

--- Id of the trophy for a number of solved level tasks in a module.
function trophies.tasks_id(module_id, count)
	return "lep_trophies:tasks:" .. module_id .. ":" .. count
end

--- Id of the trophy for a number of solved daily tasks.
function trophies.daily_id(count)
	return "lep_trophies:daily:" .. count
end

--- Name of the counter of solved level tasks of a module.
function trophies.tasks_counter(module_id)
	return "tasks:" .. module_id
end

trophies.DAILY_COUNTER = "daily"

--- Returns the material for the trophy of a stage: gold for the last
-- stage of a module, silver for the others.
function trophies.stage_material(is_last)
	return is_last and trophies.GOLD or trophies.SILVER
end

--- Returns the steps that a counter reached by going from `old` to `new`.
function trophies.steps_reached(steps, old, new)
	local reached = {}
	for _, step in ipairs(steps) do
		if old < step.count and new >= step.count then
			reached[#reached + 1] = step
		end
	end
	return reached
end

--------------------------------------------------------------------------
-- Registry

--- Creates an empty registry of trophies.
function trophies.new_registry()
	local defs = {}
	local order = {}
	local registry = {}

	--- Registers a trophy.
	-- @param id Unique id, by convention prefixed with the mod name.
	-- @param def Table with:
	--   title        name shown to players
	--   description  optional: what it was earned for
	--   material     trophies.BRONZE, SILVER or GOLD: the cup shown on a
	--                pedestal. Default bronze.
	--   node         optional: name of a node shown instead of the cup
	function registry.register(_, id, def)
		assert(type(id) == "string" and id ~= "", "trophy id must be a non-empty string")
		assert(defs[id] == nil, "trophy '" .. id .. "' is already registered")
		assert(type(def) == "table", "trophy definition must be a table")
		assert(type(def.title) == "string" and def.title ~= "",
			"trophy '" .. id .. "' needs a title")
		local material = def.material or trophies.BRONZE
		assert(MATERIALS[material], "trophy '" .. id .. "' has an unknown material")
		assert(def.node == nil or type(def.node) == "string",
			"node of trophy '" .. id .. "' must be a node name")
		defs[id] = {
			id = id,
			title = def.title,
			description = def.description or "",
			material = material,
			node = def.node,
		}
		order[#order + 1] = id
	end

	--- Returns the trophy with this id, or nil.
	function registry.get(_, id)
		return defs[id]
	end

	--- Returns all trophy ids in the order they were registered.
	function registry.ids(_)
		local copy = {}
		for index, id in ipairs(order) do
			copy[index] = id
		end
		return copy
	end

	return registry
end

--------------------------------------------------------------------------
-- State of one player

--- Returns the state of a player without trophies.
-- earned: list of trophy ids in the order they were earned.
-- slots: trophy id per pedestal number, or nil.
-- counters: number per counter name.
function trophies.new_state()
	return { earned = {}, slots = {}, counters = {} }
end

local function copy_state(state)
	local copy = trophies.new_state()
	for index, id in ipairs(state.earned) do
		copy.earned[index] = id
	end
	for slot, id in pairs(state.slots) do
		copy.slots[slot] = id
	end
	for name, count in pairs(state.counters) do
		copy.counters[name] = count
	end
	return copy
end

--- Returns true if the player has earned the trophy.
function trophies.has(state, id)
	for _, earned in ipairs(state.earned) do
		if earned == id then
			return true
		end
	end
	return false
end

--- Repairs a state that comes from storage.
-- @param slot_count Number of pedestals.
function trophies.normalize(state, slot_count)
	local result = trophies.new_state()
	if type(state) ~= "table" then
		return result
	end
	if type(state.earned) == "table" then
		for _, id in ipairs(state.earned) do
			if type(id) == "string" and not trophies.has(result, id) then
				result.earned[#result.earned + 1] = id
			end
		end
	end
	if type(state.slots) == "table" then
		local used = {}
		for slot = 1, slot_count do
			local id = state.slots[slot]
			if type(id) == "string" and trophies.has(result, id) and not used[id] then
				result.slots[slot] = id
				used[id] = true
			end
		end
	end
	if type(state.counters) == "table" then
		for name, count in pairs(state.counters) do
			if type(name) == "string" and type(count) == "number" and count > 0 then
				result.counters[name] = math.floor(count)
			end
		end
	end
	return result
end

--- Gives a trophy to a player.
-- @return new state, true if the player did not have it yet
function trophies.award(state, id)
	if trophies.has(state, id) then
		return state, false
	end
	local new_state = copy_state(state)
	new_state.earned[#new_state.earned + 1] = id
	return new_state, true
end

--- Adds to a counter.
-- @return new state, old value, new value
function trophies.count(state, counter, amount)
	local new_state = copy_state(state)
	local old = new_state.counters[counter] or 0
	new_state.counters[counter] = old + (amount or 1)
	return new_state, old, new_state.counters[counter]
end

--- Puts a trophy on a pedestal, or clears the pedestal with id nil.
-- A trophy stands on one pedestal only: it moves if it stood elsewhere.
-- @return new state  or  nil, error message
function trophies.place(state, slot, id, slot_count)
	if type(slot) ~= "number" or slot ~= math.floor(slot) or slot < 1 or slot > slot_count then
		return nil, "there is no pedestal " .. tostring(slot)
	end
	if id ~= nil and not trophies.has(state, id) then
		return nil, "the player has not earned '" .. tostring(id) .. "'"
	end
	local new_state = copy_state(state)
	if id ~= nil then
		for other = 1, slot_count do
			if new_state.slots[other] == id then
				new_state.slots[other] = nil
			end
		end
	end
	new_state.slots[slot] = id
	return new_state
end

return trophies
