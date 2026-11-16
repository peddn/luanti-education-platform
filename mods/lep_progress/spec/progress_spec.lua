local progress = dofile("mods/lep_progress/src/progress.lua")

local function new_module(levels)
	local modules = progress.new_modules()
	modules:register("test:math", {
		title = "Math",
		levels = levels or {
			{ tasks = { { id = "add", required = 2 }, { id = "sub", required = 1 } } },
			{ tasks = { { id = "mul", required = 2 } } },
			{ tasks = { { id = "div", required = 1 } } },
		},
	})
	return modules:get("test:math"), modules
end

local function names(events)
	local list = {}
	for index, event in ipairs(events) do
		list[index] = event.name
	end
	return list
end

-- Records several solved tasks and returns the last state and all events.
local function solve(module, state, level, task, times)
	local all = {}
	for _ = 1, times or 1 do
		local events
		state, events = progress.record(module, state, { level = level, task = task, solved = true })
		for _, event in ipairs(events) do
			all[#all + 1] = event
		end
	end
	return state, all
end

describe("lep_progress modules", function()
	it("accepts any number of levels", function()
		for _, count in ipairs({ 1, 3, 12 }) do
			local levels = {}
			for number = 1, count do
				levels[number] = { tasks = { { id = "t" .. number } } }
			end
			local module = new_module(levels)
			assert.are.equal(count, #module.levels)
		end
	end)

	it("uses five as default for required", function()
		local module = new_module({ { tasks = { { id = "a" }, { id = "b", required = 2 } } } })
		assert.are.equal(5, module.levels[1].by_id.a.required)
		assert.are.equal(2, module.levels[1].by_id.b.required)
	end)

	it("rejects broken definitions", function()
		local modules = progress.new_modules()
		assert.has_error(function() modules:register("", { levels = {} }) end)
		assert.has_error(function() modules:register("m", { levels = {} }) end)
		assert.has_error(function() modules:register("m", { levels = { { tasks = {} } } }) end)
		assert.has_error(function()
			modules:register("m", { levels = { { tasks = { { id = "a", required = 0 } } } } })
		end)
		assert.has_error(function()
			modules:register("m", { levels = {
				{ tasks = { { id = "a" } } }, { tasks = { { id = "a" } } },
			} })
		end)
		modules:register("m", { levels = { { tasks = { { id = "a" } } } } })
		assert.has_error(function()
			modules:register("m", { levels = { { tasks = { { id = "a" } } } } })
		end)
	end)

	it("marks stages, and always the last level", function()
		local module = new_module({
			{ tasks = { { id = "a" } } },
			{ stage = true, tasks = { { id = "b" } } },
			{ tasks = { { id = "c" } } },
			{ tasks = { { id = "d" } } },
		})
		assert.are.same({ false, true, false, true }, {
			module.levels[1].stage, module.levels[2].stage,
			module.levels[3].stage, module.levels[4].stage,
		})
	end)

	it("lists modules in the order they were registered", function()
		local _, modules = new_module()
		modules:register("test:quiz", { levels = { { tasks = { { id = "q" } } } } })
		assert.are.same({ "test:math", "test:quiz" }, modules:ids())
		assert.is_nil(modules:get("test:none"))
	end)
end)

describe("lep_progress record", function()
	local module

	before_each(function()
		module = new_module()
	end)

	it("starts on level 1 with nothing done", function()
		local state = progress.new_state()
		assert.are.equal(1, state.level)
		assert.are.equal(0, progress.percent(module, state, 1))
		assert.is_false(progress.is_module_completed(module, state))
	end)

	it("counts solved tasks and reports the share of done task types", function()
		local state, events = solve(module, progress.new_state(), 1, "add")
		assert.are.equal(1, progress.solved_count(state, 1, "add"))
		assert.are.equal(0, progress.percent(module, state, 1))
		assert.are.same({}, events)
		state = solve(module, state, 1, "add")
		assert.are.equal(50, progress.percent(module, state, 1))
		assert.are.same({ 1, 2 }, { progress.done_tasks(module, state, 1) })
	end)

	it("does not count wrong answers and takes nothing away", function()
		local state = solve(module, progress.new_state(), 1, "add")
		local after, events, counted = progress.record(module, state,
			{ level = 1, task = "add", solved = false })
		assert.are.equal(1, progress.solved_count(after, 1, "add"))
		assert.are.same({}, events)
		assert.is_false(counted)
	end)

	it("does not count more than required", function()
		local state = solve(module, progress.new_state(), 1, "add", 5)
		assert.are.equal(2, progress.solved_count(state, 1, "add"))
	end)

	it("does not change the state it was given", function()
		local state = progress.new_state()
		solve(module, state, 1, "add", 2)
		assert.are.same(progress.new_state(), state)
	end)

	it("completes a level and moves the player up", function()
		local state = solve(module, progress.new_state(), 1, "add", 2)
		local events
		state, events = solve(module, state, 1, "sub")
		assert.are.same({ progress.LEVEL_COMPLETED, progress.LEVEL_CHANGED }, names(events))
		assert.are.equal(1, events[1].level)
		assert.is_false(events[1].stage)
		assert.are.equal(1, events[2].old_level)
		assert.are.equal(2, events[2].new_level)
		assert.are.equal(progress.REASON_COMPLETED, events[2].reason)
		assert.are.equal(2, state.level)
		assert.are.equal(100, progress.percent(module, state, 1))
	end)

	it("stays on the level when moving up is locked", function()
		local state = progress.set_locked(module, progress.new_state(), true)
		state = solve(module, state, 1, "add", 2)
		local events
		state, events = solve(module, state, 1, "sub")
		assert.are.same({ progress.LEVEL_COMPLETED }, names(events))
		assert.are.equal(1, state.level)

		state, events = progress.set_locked(module, state, false)
		assert.are.same({ progress.LEVEL_CHANGED }, names(events))
		assert.are.equal(2, state.level)
	end)

	it("completes the module after the last level", function()
		local state = solve(module, progress.new_state(), 1, "add", 2)
		state = solve(module, state, 1, "sub")
		state = solve(module, state, 2, "mul", 2)
		assert.are.equal(3, state.level)
		local events
		state, events = solve(module, state, 3, "div")
		assert.are.same({ progress.LEVEL_COMPLETED, progress.MODULE_COMPLETED }, names(events))
		assert.is_true(events[1].stage)
		assert.are.equal(3, state.level)
		assert.is_true(progress.is_module_completed(module, state))

		-- Further tasks are still accepted and change nothing.
		local after, more = solve(module, state, 3, "div")
		assert.are.same({}, more)
		assert.are.same(state, after)
	end)

	it("ignores tasks of other levels for the workload", function()
		local state, events, counted = progress.record(module, progress.new_state(),
			{ level = 2, task = "mul", solved = true })
		assert.is_false(counted)
		assert.are.same({}, events)
		assert.are.equal(0, progress.solved_count(state, 2, "mul"))
	end)

	it("never counts daily tasks for the workload", function()
		local state, events, counted = progress.record(module, progress.new_state(),
			{ level = 1, task = "add", solved = true, kind = progress.KIND_DAILY })
		assert.is_false(counted)
		assert.are.same({}, events)
		assert.are.equal(0, progress.solved_count(state, 1, "add"))
	end)

	it("rejects results the module cannot have produced", function()
		assert.is_nil(progress.check_result(module, 4, "add"))
		assert.is_nil(progress.check_result(module, 0, "add"))
		assert.is_nil(progress.check_result(module, 1, "mul"))
		assert.is_nil(progress.check_result(module, 1.5, "add"))
		assert.is_true(progress.check_result(module, 2, "mul"))
		assert.has_error(function()
			progress.record(module, progress.new_state(), { level = 1, task = "mul", solved = true })
		end)
	end)
end)

describe("lep_progress set_level", function()
	local module

	before_each(function()
		module = new_module()
	end)

	it("changes the level and keeps the counts of all levels", function()
		local state = solve(module, progress.new_state(), 1, "add")
		local events
		state, events = progress.set_level(module, state, 2)
		assert.are.same({ progress.LEVEL_CHANGED }, names(events))
		assert.are.equal(progress.REASON_TEACHER, events[1].reason)
		state = solve(module, state, 2, "mul")
		state = progress.set_level(module, state, 1)
		assert.are.equal(1, progress.solved_count(state, 1, "add"))
		assert.are.equal(1, progress.solved_count(state, 2, "mul"))
	end)

	it("reports nothing when the level stays the same", function()
		local _, events = progress.set_level(module, progress.new_state(), 1)
		assert.are.same({}, events)
	end)

	it("rejects levels the module does not have", function()
		assert.is_nil(progress.set_level(module, progress.new_state(), 0))
		assert.is_nil(progress.set_level(module, progress.new_state(), 4))
		assert.is_nil(progress.set_level(module, progress.new_state(), "2"))
	end)

	it("does not move a player up who was put back on a completed level", function()
		local state = solve(module, progress.new_state(), 1, "add", 2)
		state = solve(module, state, 1, "sub")
		state = progress.set_level(module, state, 1)
		local events
		state, events = solve(module, state, 1, "add")
		assert.are.same({}, events)
		assert.are.equal(1, state.level)
	end)
end)

describe("lep_progress normalize", function()
	local module = new_module()

	it("returns a fresh state for broken data", function()
		assert.are.same(progress.new_state(), progress.normalize(module, nil))
		assert.are.same(progress.new_state(), progress.normalize(module, "nonsense"))
	end)

	it("keeps valid data", function()
		local state = solve(module, progress.new_state(), 1, "add", 2)
		state = solve(module, state, 1, "sub")
		state = progress.set_locked(module, state, true)
		assert.are.same(state, progress.normalize(module, state))
	end)

	it("repairs levels, counts and unknown task types", function()
		local state = progress.normalize(module, {
			level = 9,
			locked = "yes",
			completed = { [1] = true, [7] = true },
			solved = { [1] = { add = 99, gone = 3, sub = -1 }, [8] = { x = 1 } },
		})
		assert.are.equal(3, state.level)
		assert.is_false(state.locked)
		assert.are.same({ [1] = true }, state.completed)
		assert.are.same({ [1] = { add = 2 } }, state.solved)
	end)
end)
