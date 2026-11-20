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

	it("marks stages, but never the last level: it ends the module", function()
		local module = new_module({
			{ tasks = { { id = "a" } } },
			{ stage = true, tasks = { { id = "b" } } },
			{ tasks = { { id = "c" } } },
			{ stage = true, tasks = { { id = "d" } } },
		})
		assert.are.same({ false, true, false, false }, {
			module.levels[1].stage, module.levels[2].stage,
			module.levels[3].stage, module.levels[4].stage,
		})
	end)

	it("knows how hard a module is, low unless it says so", function()
		local module, modules = new_module()
		assert.are.equal(progress.EFFORT_LOW, module.effort)
		modules:register("test:quiz", { effort = progress.EFFORT_HIGH,
			levels = { { tasks = { { id = "q" } } } } })
		assert.are.equal(progress.EFFORT_HIGH, modules:get("test:quiz").effort)
		assert.has_error(function()
			modules:register("test:odd", { effort = "huge",
				levels = { { tasks = { { id = "q" } } } } })
		end)
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

	it("counts solved tasks and reports the share of the workload", function()
		-- Level 1 asks for three tasks: two of one type, one of another.
		local state, events = solve(module, progress.new_state(), 1, "add")
		assert.are.equal(1, progress.solved_count(state, 1, "add"))
		assert.are.equal(33, progress.percent(module, state, 1))
		assert.are.same({}, events)
		state = solve(module, state, 1, "add")
		assert.are.equal(66, progress.percent(module, state, 1))
		assert.are.same({ 1, 2 }, { progress.done_tasks(module, state, 1) })
		-- More than required moves nothing.
		state = solve(module, state, 1, "add")
		assert.are.equal(66, progress.percent(module, state, 1))
	end)

	it("moves the share with every task, not only with a finished type", function()
		local wide = new_module({
			{ tasks = { { id = "a", required = 5 }, { id = "b", required = 5 } } },
		})
		local state = solve(wide, progress.new_state(), 1, "a", 4)
		assert.are.equal(40, progress.percent(wide, state, 1))
		assert.are.same({ 0, 2 }, { progress.done_tasks(wide, state, 1) })
		state = solve(wide, state, 1, "b", 5)
		assert.are.equal(90, progress.percent(wide, state, 1))
		state = solve(wide, state, 1, "a")
		assert.are.equal(100, progress.percent(wide, state, 1))
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
		-- The last level is no stage: it ends the module.
		assert.is_false(events[1].stage)
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

	it("lets a player repeat a completed level and move up again", function()
		local state = solve(module, progress.new_state(), 1, "add", 2)
		state = solve(module, state, 1, "sub")
		state = solve(module, state, 2, "mul")
		assert.are.equal(2, state.level)

		-- Back on level 1: its workload starts again, level 2 keeps its count.
		state = progress.set_level(module, state, 1)
		assert.are.equal(0, progress.percent(module, state, 1))
		assert.are.equal(0, progress.solved_count(state, 1, "add"))
		assert.are.equal(1, progress.solved_count(state, 2, "mul"))

		-- The tasks count again.
		local events, counted
		state, events, counted = progress.record(module, state,
			{ level = 1, task = "add", solved = true })
		assert.is_true(counted)
		assert.are.same({}, events)
		assert.are.equal(33, progress.percent(module, state, 1))

		-- With the workload done the player moves up, but the level is
		-- not reported as completed a second time.
		state = solve(module, state, 1, "add")
		state, events = solve(module, state, 1, "sub")
		assert.are.same({ progress.LEVEL_CHANGED }, names(events))
		assert.are.equal(progress.REASON_COMPLETED, events[1].reason)
		assert.are.equal(2, state.level)
		assert.are.equal(1, progress.solved_count(state, 2, "mul"))
	end)

	it("does not move a player up who is in the middle of repeating", function()
		local state = solve(module, progress.new_state(), 1, "add", 2)
		state = solve(module, state, 1, "sub")
		state = progress.set_level(module, state, 1)
		state = solve(module, state, 1, "add")
		-- Locking and unlocking is no way around the workload.
		state = progress.set_locked(module, state, true)
		local events
		state, events = progress.set_locked(module, state, false)
		assert.are.same({}, events)
		assert.are.equal(1, state.level)

		-- Locked, the player stays even with the workload done again.
		state = progress.set_locked(module, state, true)
		state = solve(module, state, 1, "add")
		state, events = solve(module, state, 1, "sub")
		assert.are.same({}, events)
		assert.are.equal(1, state.level)
		state, events = progress.set_locked(module, state, false)
		assert.are.same({ progress.LEVEL_CHANGED }, names(events))
		assert.are.equal(2, state.level)
	end)

	it("keeps the counts of a level that was not completed", function()
		local state = solve(module, progress.new_state(), 1, "add")
		state = progress.set_level(module, state, 2)
		state = progress.set_level(module, state, 1)
		assert.are.equal(1, progress.solved_count(state, 1, "add"))
		-- Setting the level a player is on changes nothing either.
		state = progress.set_level(module, state, 1)
		assert.are.equal(1, progress.solved_count(state, 1, "add"))
	end)

	it("repeats the last level without completing the module again", function()
		local state = progress.set_level(module, progress.new_state(), 3)
		local events
		state, events = solve(module, state, 3, "div")
		assert.are.same({ progress.LEVEL_COMPLETED, progress.MODULE_COMPLETED }, names(events))
		state = progress.set_level(module, state, 3)
		assert.are.equal(0, progress.percent(module, state, 3))
		assert.is_true(progress.is_module_completed(module, state))
		state, events = solve(module, state, 3, "div")
		assert.are.same({}, events)
		assert.are.equal(100, progress.percent(module, state, 3))
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
	it("puts a player nothing is stored about on the start level", function()
		local fresh = progress.normalize(module, nil, 2)
		assert.are.equal(2, fresh.level)
		-- The levels below were skipped, not completed: no rewards for them.
		assert.are.same({}, fresh.completed)
		assert.are.same({}, fresh.solved)
		assert.is_false(fresh.locked)
	end)

	it("leaves a player alone who has a stored state", function()
		local state = solve(module, progress.new_state(), 1, "add")
		assert.are.equal(1, progress.normalize(module, state, 3).level)
		-- A level a teacher set by hand counts as well.
		local set = progress.set_level(module, progress.new_state(), 2)
		assert.are.equal(2, progress.normalize(module, set, 3).level)
	end)

	it("falls back to level 1 for a start level the module does not have", function()
		for _, bad in ipairs({ 0, 4, 1.5, "2", -1 }) do
			assert.are.equal(1, progress.start_level(module, bad))
			assert.is_false(progress.is_start_level(module, bad))
			assert.are.equal(1, progress.normalize(module, nil, bad).level)
		end
		assert.are.equal(1, progress.start_level(module, nil))
		assert.is_true(progress.is_start_level(module, 1))
		assert.is_true(progress.is_start_level(module, 3))
	end)

	it("counts the first task on the start level", function()
		local state = solve(module, progress.normalize(module, nil, 2), 2, "mul")
		assert.are.equal(2, state.level)
		assert.are.equal(1, state.solved[2].mul)
	end)
end)
