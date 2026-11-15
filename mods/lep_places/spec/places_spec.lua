local places = dofile("mods/lep_places/src/places.lua")

local WILD = "test:wilderness"
local LOBBY = "test:lobby"
local ROOM = "test:room"
local ROOM2 = "test:room2"

local function new_registry()
	local registry = places.new_registry()
	registry:register(WILD, { remember_position = true })
	registry:register(LOBBY, { default_pos = { x = 0, y = 100, z = 0 } })
	registry:register(ROOM, {
		inventory = "learning",
		privileges = { fly = true },
		default_pos = { x = 0, y = 200, z = 0 },
	})
	registry:register(ROOM2, {
		inventory = "learning",
		default_pos = { x = 0, y = 300, z = 0 },
	})
	return registry
end

local function ops(steps)
	local result = {}
	for i, step in ipairs(steps) do
		result[i] = step.op
	end
	return result
end

local function find(steps, op)
	for _, step in ipairs(steps) do
		if step.op == op then
			return step
		end
	end
end

local HERE = { x = 10, y = 5, z = -3 }

describe("lep_places registry", function()
	it("stores a definition with defaults", function()
		local registry = places.new_registry()
		registry:register("a", {})
		local def = registry:get("a")
		assert.are.equal("a", def.id)
		assert.are.equal("survival", def.inventory)
		assert.is_false(def.remember_position)
		assert.are.same({}, def.privileges)
	end)

	it("returns nil for unknown places", function()
		assert.is_nil(places.new_registry():get("nope"))
	end)

	it("rejects duplicate ids", function()
		local registry = places.new_registry()
		registry:register("a", {})
		assert.has_error(function() registry:register("a", {}) end)
	end)

	it("rejects invalid definitions", function()
		local registry = places.new_registry()
		assert.has_error(function() registry:register("", {}) end)
		assert.has_error(function() registry:register("a", nil) end)
		assert.has_error(function() registry:register("a", { inventory = "x" }) end)
		assert.has_error(function() registry:register("a", { default_pos = 5 }) end)
	end)

	it("copies the definition so later changes have no effect", function()
		local registry = places.new_registry()
		local privileges = { fly = true }
		registry:register("a", { privileges = privileges })
		privileges.noclip = true
		assert.is_nil(registry:get("a").privileges.noclip)
	end)
end)

describe("lep_places state", function()
	it("creates an initial state", function()
		local state = places.initial_state(WILD)
		assert.are.equal(WILD, state.place)
		assert.is_false(state.survival_stored)
		assert.are.same({}, state.granted)
		assert.are.same({}, state.positions)
	end)

	it("normalizes missing or broken data", function()
		assert.are.same(places.initial_state(WILD), places.normalize_state(nil, WILD))
		assert.are.same(places.initial_state(WILD),
			places.normalize_state("garbage", WILD))

		local state = places.normalize_state({
			place = 7,
			positions = { [WILD] = "broken", [LOBBY] = { x = 1, y = 2, z = 3 } },
			granted = { fly = true, fast = false },
			survival_stored = "yes",
		}, WILD)
		assert.are.equal(WILD, state.place)
		assert.are.same({ [LOBBY] = { x = 1, y = 2, z = 3 } }, state.positions)
		assert.are.same({ fly = true }, state.granted)
		assert.is_false(state.survival_stored)
	end)
end)

describe("lep_places plan_move", function()
	local registry

	before_each(function()
		registry = new_registry()
	end)

	it("moves between survival places without touching the inventory", function()
		local steps, state = places.plan_move(registry, places.initial_state(WILD), {
			target = LOBBY, current_pos = HERE, current_privs = {},
		})
		assert.are.same({ "teleport" }, ops(steps))
		assert.are.same({ x = 0, y = 100, z = 0 }, steps[1].pos)
		assert.are.equal(LOBBY, state.place)
		assert.is_false(state.survival_stored)
	end)

	it("remembers the position when leaving a place that asks for it", function()
		local _, state = places.plan_move(registry, places.initial_state(WILD), {
			target = LOBBY, current_pos = HERE, current_privs = {},
		})
		assert.are.same(HERE, state.positions[WILD])
	end)

	it("returns to the remembered position", function()
		local _, in_lobby = places.plan_move(registry, places.initial_state(WILD), {
			target = LOBBY, current_pos = HERE, current_privs = {},
		})
		local steps = places.plan_move(registry, in_lobby, {
			target = WILD, current_pos = { x = 0, y = 100, z = 0 }, current_privs = {},
		})
		assert.are.same(HERE, find(steps, "teleport").pos)
	end)

	it("prefers an explicit position over the remembered one", function()
		local _, in_lobby = places.plan_move(registry, places.initial_state(WILD), {
			target = LOBBY, current_pos = HERE, current_privs = {},
		})
		local explicit = { x = 99, y = 9, z = 9 }
		local steps = places.plan_move(registry, in_lobby, {
			target = WILD, pos = explicit,
			current_pos = { x = 0, y = 100, z = 0 }, current_privs = {},
		})
		assert.are.same(explicit, find(steps, "teleport").pos)
	end)

	it("does not remember positions of places that do not ask for it", function()
		local in_lobby = places.initial_state(LOBBY)
		local _, state = places.plan_move(registry, in_lobby, {
			target = ROOM, current_pos = HERE, current_privs = {},
		})
		assert.is_nil(state.positions[LOBBY])
	end)

	it("keeps the remembered position when moving within the same place", function()
		local state = places.initial_state(WILD)
		state.positions[WILD] = { x = 1, y = 1, z = 1 }
		local steps, new_state = places.plan_move(registry, state, {
			target = WILD, pos = { x = 50, y = 5, z = 50 },
			current_pos = HERE, current_privs = {},
		})
		assert.are.same({ "teleport" }, ops(steps))
		assert.are.same({ x = 1, y = 1, z = 1 }, new_state.positions[WILD])
	end)

	it("stores and clears the survival inventory when entering a room", function()
		local steps, state = places.plan_move(registry, places.initial_state(WILD), {
			target = ROOM, current_pos = HERE, current_privs = {},
		})
		assert.are.same({ "store_survival", "clear_inventory", "grant", "teleport" },
			ops(steps))
		assert.is_true(state.survival_stored)
	end)

	it("restores the survival inventory when leaving a room", function()
		local _, in_room = places.plan_move(registry, places.initial_state(WILD), {
			target = ROOM, current_pos = HERE, current_privs = {},
		})
		local steps, state = places.plan_move(registry, in_room, {
			target = WILD, current_pos = { x = 0, y = 200, z = 0 },
			current_privs = { fly = true },
		})
		assert.are.same(
			{ "clear_inventory", "restore_survival", "revoke", "teleport" },
			ops(steps))
		assert.is_false(state.survival_stored)
	end)

	it("never stores the survival inventory twice", function()
		local _, in_room = places.plan_move(registry, places.initial_state(WILD), {
			target = ROOM, current_pos = HERE, current_privs = {},
		})
		local steps, state = places.plan_move(registry, in_room, {
			target = ROOM2, current_pos = HERE, current_privs = { fly = true },
		})
		assert.is_nil(find(steps, "store_survival"))
		assert.is_truthy(find(steps, "clear_inventory"))
		assert.is_true(state.survival_stored)
	end)

	it("grants privileges of the target place and records them", function()
		local steps, state = places.plan_move(registry, places.initial_state(WILD), {
			target = ROOM, current_pos = HERE, current_privs = { interact = true },
		})
		assert.are.same({ "fly" }, find(steps, "grant").privileges)
		assert.are.same({ fly = true }, state.granted)
	end)

	it("revokes only privileges it granted itself", function()
		-- A teacher already has fly before entering the room.
		local _, in_room = places.plan_move(registry, places.initial_state(WILD), {
			target = ROOM, current_pos = HERE, current_privs = { fly = true },
		})
		assert.are.same({}, in_room.granted)

		local steps = places.plan_move(registry, in_room, {
			target = WILD, current_pos = HERE, current_privs = { fly = true },
		})
		assert.is_nil(find(steps, "revoke"))
	end)

	it("keeps a granted privilege when the next place wants it too", function()
		registry:register("test:room3", {
			inventory = "learning",
			privileges = { fly = true },
			default_pos = { x = 0, y = 400, z = 0 },
		})
		local _, in_room = places.plan_move(registry, places.initial_state(WILD), {
			target = ROOM, current_pos = HERE, current_privs = {},
		})
		local steps, state = places.plan_move(registry, in_room, {
			target = "test:room3", current_pos = HERE, current_privs = { fly = true },
		})
		assert.is_nil(find(steps, "revoke"))
		assert.is_nil(find(steps, "grant"))
		assert.are.same({ fly = true }, state.granted)
	end)

	it("grants a kept privilege again if it was lost in between", function()
		registry:register("test:room3", {
			inventory = "learning",
			privileges = { fly = true },
			default_pos = { x = 0, y = 400, z = 0 },
		})
		local _, in_room = places.plan_move(registry, places.initial_state(WILD), {
			target = ROOM, current_pos = HERE, current_privs = {},
		})
		local steps = places.plan_move(registry, in_room, {
			target = "test:room3", current_pos = HERE, current_privs = {},
		})
		assert.are.same({ "fly" }, find(steps, "grant").privileges)
	end)

	it("teleports last", function()
		local steps = places.plan_move(registry, places.initial_state(WILD), {
			target = ROOM, current_pos = HERE, current_privs = {},
		})
		assert.are.equal("teleport", steps[#steps].op)
	end)

	it("does not modify the given state", function()
		local state = places.initial_state(WILD)
		places.plan_move(registry, state, {
			target = ROOM, current_pos = HERE, current_privs = {},
		})
		assert.are.same(places.initial_state(WILD), state)
	end)

	it("fails for unknown places", function()
		local steps, err = places.plan_move(registry, places.initial_state(WILD), {
			target = "test:nowhere", current_pos = HERE, current_privs = {},
		})
		assert.is_nil(steps)
		assert.is_truthy(err:find("unknown place", 1, true))
	end)

	it("fails when no position is known", function()
		registry:register("test:nopos", {})
		local steps, err = places.plan_move(registry, places.initial_state(WILD), {
			target = "test:nopos", current_pos = HERE, current_privs = {},
		})
		assert.is_nil(steps)
		assert.is_truthy(err:find("no position", 1, true))
	end)

	it("fails for invalid positions", function()
		local state = places.initial_state(WILD)
		assert.is_nil((places.plan_move(registry, state, {
			target = LOBBY, pos = "here", current_pos = HERE, current_privs = {},
		})))
		assert.is_nil((places.plan_move(registry, state, {
			target = LOBBY, current_pos = nil, current_privs = {},
		})))
	end)

	it("still works when the current place is no longer registered", function()
		local state = places.initial_state("test:removed")
		local steps, new_state = places.plan_move(registry, state, {
			target = LOBBY, current_pos = HERE, current_privs = {},
		})
		assert.are.same({ "teleport" }, ops(steps))
		assert.are.equal(LOBBY, new_state.place)
	end)
end)

describe("lep_places plan_join", function()
	local registry

	before_each(function()
		registry = new_registry()
	end)

	it("does nothing for a consistent survival state", function()
		local steps, state = places.plan_join(registry, places.initial_state(WILD),
			WILD, { interact = true })
		assert.are.same({}, steps)
		assert.are.equal(WILD, state.place)
	end)

	it("revokes a leftover privilege after a crash", function()
		-- State says wilderness, but fly was granted and never revoked.
		local state = places.initial_state(WILD)
		state.granted = { fly = true }
		local steps, new_state = places.plan_join(registry, state, WILD,
			{ fly = true })
		assert.are.same({ "fly" }, find(steps, "revoke").privileges)
		assert.are.same({}, new_state.granted)
	end)

	it("grants a missing privilege of the current place", function()
		local state = places.initial_state(ROOM)
		state.survival_stored = true
		local steps, new_state = places.plan_join(registry, state, WILD, {})
		assert.are.same({ "fly" }, find(steps, "grant").privileges)
		assert.are.same({ fly = true }, new_state.granted)
		assert.is_true(new_state.survival_stored)
	end)

	it("falls back when the stored place no longer exists", function()
		local state = places.initial_state("test:removed")
		state.survival_stored = true
		state.granted = { fly = true }
		local steps, new_state = places.plan_join(registry, state, WILD,
			{ fly = true })
		assert.are.same({ "clear_inventory", "restore_survival", "revoke" }, ops(steps))
		assert.are.equal(WILD, new_state.place)
		assert.is_false(new_state.survival_stored)
	end)

	it("never teleports", function()
		local state = places.initial_state("test:removed")
		local steps = places.plan_join(registry, state, WILD, {})
		assert.is_nil(find(steps, "teleport"))
	end)
end)
