local trophies = dofile("mods/lep_trophies/src/trophies.lua")

local SLOTS = 6

local function with(ids)
	local state = trophies.new_state()
	for _, id in ipairs(ids) do
		state = trophies.award(state, id)
	end
	return state
end

describe("lep_trophies registry", function()
	it("registers trophies with bronze as default", function()
		local registry = trophies.new_registry()
		registry:register("test:a", { title = "A" })
		registry:register("test:b", { title = "B", material = trophies.GOLD, description = "why" })
		assert.are.equal(trophies.BRONZE, registry:get("test:a").material)
		assert.are.equal("", registry:get("test:a").description)
		assert.are.equal(trophies.GOLD, registry:get("test:b").material)
		assert.are.same({ "test:a", "test:b" }, registry:ids())
		assert.is_nil(registry:get("test:none"))
	end)

	it("rejects broken definitions", function()
		local registry = trophies.new_registry()
		registry:register("test:a", { title = "A" })
		assert.has_error(function() registry:register("test:a", { title = "A" }) end)
		assert.has_error(function() registry:register("", { title = "A" }) end)
		assert.has_error(function() registry:register("test:b", {}) end)
		assert.has_error(function() registry:register("test:b", { title = "B", material = "tin" }) end)
		assert.has_error(function() registry:register("test:b", { title = "B", node = 5 }) end)
	end)
end)

describe("lep_trophies milestones", function()
	it("builds different ids for different milestones", function()
		local ids = {
			trophies.stage_id("m:a", 2), trophies.stage_id("m:a", 4), trophies.stage_id("m:b", 2),
			trophies.tasks_id("m:a", 10), trophies.tasks_id("m:a", 50), trophies.daily_id(10),
		}
		local seen = {}
		for _, id in ipairs(ids) do
			assert.is_nil(seen[id])
			seen[id] = true
		end
		assert.are.not_equal(trophies.tasks_counter("m:a"), trophies.DAILY_COUNTER)
	end)

	it("gives gold for the last stage and silver for the others", function()
		assert.are.equal(trophies.SILVER, trophies.STAGE_MATERIAL)
		assert.are.equal(trophies.GOLD, trophies.MODULE_MATERIAL)
		assert.are.equal("lep_trophies:module:m:a", trophies.module_id("m:a"))
		assert.are_not.equal(trophies.module_id("m:a"), trophies.stage_id("m:a", 4))
	end)

	it("finds the steps a counter reached", function()
		local function counts(old, new)
			local list = {}
			for _, step in ipairs(trophies.steps_reached(trophies.TASK_STEPS, old, new)) do
				list[#list + 1] = step.count
			end
			return list
		end
		assert.are.same({}, counts(0, 9))
		assert.are.same({ 10 }, counts(9, 10))
		assert.are.same({}, counts(10, 11))
		assert.are.same({ 50 }, counts(49, 50))
		assert.are.same({ 10, 50, 100 }, counts(0, 500))
	end)
end)

describe("lep_trophies player state", function()
	it("awards a trophy only once and keeps the order", function()
		local state, is_new = trophies.award(trophies.new_state(), "a")
		assert.is_true(is_new)
		state = trophies.award(state, "b")
		local again
		state, again = trophies.award(state, "a")
		assert.is_false(again)
		assert.are.same({ "a", "b" }, state.earned)
		assert.is_true(trophies.has(state, "b"))
		assert.is_false(trophies.has(state, "c"))
	end)

	it("counts", function()
		local state, old, new = trophies.count(trophies.new_state(), "daily")
		assert.are.same({ 0, 1 }, { old, new })
		state, old, new = trophies.count(state, "daily", 9)
		assert.are.same({ 1, 10 }, { old, new })
		assert.are.equal(10, state.counters.daily)
	end)

	it("does not change the state it was given", function()
		local state = trophies.new_state()
		trophies.award(state, "a")
		trophies.count(state, "daily")
		assert.are.same(trophies.new_state(), state)
	end)

	it("puts an earned trophy on a pedestal", function()
		local state = trophies.place(with({ "a", "b" }), 3, "b", SLOTS)
		assert.are.equal("b", state.slots[3])
	end)

	it("moves a trophy that already stands elsewhere", function()
		local state = trophies.place(with({ "a", "b" }), 1, "a", SLOTS)
		state = trophies.place(state, 5, "a", SLOTS)
		assert.is_nil(state.slots[1])
		assert.are.equal("a", state.slots[5])
	end)

	it("replaces the trophy on a pedestal and clears it", function()
		local state = trophies.place(with({ "a", "b" }), 2, "a", SLOTS)
		state = trophies.place(state, 2, "b", SLOTS)
		assert.are.equal("b", state.slots[2])
		state = trophies.place(state, 2, nil, SLOTS)
		assert.is_nil(state.slots[2])
	end)

	it("refuses trophies the player has not earned and pedestals that do not exist", function()
		local state = with({ "a" })
		assert.is_nil(trophies.place(state, 1, "b", SLOTS))
		assert.is_nil(trophies.place(state, 0, "a", SLOTS))
		assert.is_nil(trophies.place(state, 7, "a", SLOTS))
		assert.is_nil(trophies.place(state, 1.5, "a", SLOTS))
		assert.is_nil(trophies.place(state, "1", "a", SLOTS))
	end)

	it("repairs stored data", function()
		assert.are.same(trophies.new_state(), trophies.normalize(nil, SLOTS))
		local state = trophies.normalize({
			earned = { "a", "b", "a", 7 },
			slots = { [1] = "a", [2] = "a", [3] = "zzz", [4] = "b", [9] = "b" },
			counters = { daily = 3.9, bad = -1, [5] = 2, text = "x" },
		}, SLOTS)
		assert.are.same({ "a", "b" }, state.earned)
		assert.are.same({ [1] = "a", [4] = "b" }, state.slots)
		assert.are.same({ daily = 3 }, state.counters)
	end)
end)
