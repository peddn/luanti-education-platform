-- Levels and workload of the learning modules. Pure Lua, no engine calls.
--
-- A module has any number of levels, counted from 1. Every level has a
-- fixed list of task types, its workload. A task type is done once the
-- player solved it a certain number of times. A level is completed when
-- all its task types are done. The player then moves up one level, unless
-- the teacher locked that.

local progress = {}

-- How often a task type has to be solved, unless the module says otherwise.
progress.DEFAULT_REQUIRED = 5

-- Events returned by the functions below, as { name = ..., ... } tables.
progress.LEVEL_COMPLETED = "level_completed"   -- level, stage
progress.LEVEL_CHANGED = "level_changed"       -- old_level, new_level, reason
progress.MODULE_COMPLETED = "module_completed"

-- Where a task came from.
progress.KIND_TASK = "task"
progress.KIND_CHEST = "chest"

-- Reasons for a level change.
progress.REASON_COMPLETED = "completed"
progress.REASON_TEACHER = "teacher"

--------------------------------------------------------------------------
-- Modules

local function check_id(value, what)
	assert(type(value) == "string" and value ~= "", what .. " must be a non-empty string")
end

--- Creates an empty registry of modules.
function progress.new_modules()
	local modules = {}
	local order = {}
	local registry = {}

	--- Registers a module.
	-- @param id Module id, for example "lep_math:math".
	-- @param def Table with:
	--   title   name shown to players
	--   levels  list of levels, each a table with
	--     title  optional name of the level
	--     stage  optional: true if completing this level ends a stage.
	--            The last level always ends one.
	--     tasks  list of task types, each a table with
	--       id        id of the task type, unique within the module
	--       title     name shown to players
	--       required  optional: how often it has to be solved
	function registry.register(_, id, def)
		check_id(id, "module id")
		assert(modules[id] == nil, "module '" .. id .. "' is already registered")
		assert(type(def) == "table", "module definition must be a table")
		assert(type(def.levels) == "table" and #def.levels >= 1,
			"module '" .. id .. "' needs at least one level")

		local levels = {}
		local seen = {}
		for number, level in ipairs(def.levels) do
			assert(type(level) == "table" and type(level.tasks) == "table"
				and #level.tasks >= 1,
				"level " .. number .. " of '" .. id .. "' needs at least one task type")
			local tasks = {}
			local by_id = {}
			for index, task in ipairs(level.tasks) do
				assert(type(task) == "table", "task type must be a table")
				check_id(task.id, "task type id")
				assert(not seen[task.id],
					"task type '" .. task.id .. "' appears twice in '" .. id .. "'")
				seen[task.id] = true
				local required = task.required or progress.DEFAULT_REQUIRED
				assert(type(required) == "number" and required >= 1
					and required == math.floor(required),
					"required of '" .. task.id .. "' must be a positive integer")
				tasks[index] = {
					id = task.id,
					title = task.title or task.id,
					required = required,
				}
				by_id[task.id] = tasks[index]
			end
			levels[number] = {
				title = level.title or tostring(number),
				stage = level.stage == true or number == #def.levels,
				tasks = tasks,
				by_id = by_id,
			}
		end

		modules[id] = { id = id, title = def.title or id, levels = levels }
		order[#order + 1] = id
	end

	--- Returns the module with this id, or nil.
	function registry.get(_, id)
		return modules[id]
	end

	--- Returns all module ids in the order they were registered.
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
-- State of one player in one module

--- Returns the state of a player who has not done anything in a module.
function progress.new_state()
	return { level = 1, locked = false, completed = {}, solved = {} }
end

--- Repairs a state that comes from storage, for the given module.
function progress.normalize(module, state)
	local result = progress.new_state()
	if type(state) ~= "table" then
		return result
	end
	local last = #module.levels

	if type(state.level) == "number" and state.level == math.floor(state.level) then
		result.level = math.max(1, math.min(last, state.level))
	end
	result.locked = state.locked == true

	for number = 1, last do
		if type(state.completed) == "table" and state.completed[number] == true then
			result.completed[number] = true
		end
		local counts = type(state.solved) == "table" and state.solved[number]
		if type(counts) == "table" then
			local kept = {}
			for _, task in ipairs(module.levels[number].tasks) do
				local count = counts[task.id]
				if type(count) == "number" and count > 0 then
					kept[task.id] = math.min(task.required, math.floor(count))
				end
			end
			if next(kept) then
				result.solved[number] = kept
			end
		end
	end
	return result
end

local function copy_state(state)
	local copy = { level = state.level, locked = state.locked, completed = {}, solved = {} }
	for number, done in pairs(state.completed) do
		copy.completed[number] = done
	end
	for number, counts in pairs(state.solved) do
		copy.solved[number] = {}
		for task_id, count in pairs(counts) do
			copy.solved[number][task_id] = count
		end
	end
	return copy
end

--- Returns how often a task type has been solved on a level.
function progress.solved_count(state, level, task_id)
	return (state.solved[level] or {})[task_id] or 0
end

--- Returns how many task types of a level are done, and how many it has.
function progress.done_tasks(module, state, level)
	local tasks = module.levels[level].tasks
	local done = 0
	for _, task in ipairs(tasks) do
		if progress.solved_count(state, level, task.id) >= task.required then
			done = done + 1
		end
	end
	return done, #tasks
end

--- Returns the share of done task types of a level in percent, 0 to 100.
function progress.percent(module, state, level)
	local done, total = progress.done_tasks(module, state, level)
	return math.floor(done * 100 / total)
end

--- Returns true if the player completed the last level of the module.
function progress.is_module_completed(module, state)
	return state.completed[#module.levels] == true
end

-- Moves the player up after completing their level, if allowed.
local function move_up(module, state, events)
	if state.locked or not state.completed[state.level]
			or state.level >= #module.levels then
		return
	end
	local old = state.level
	state.level = old + 1
	events[#events + 1] = {
		name = progress.LEVEL_CHANGED,
		old_level = old,
		new_level = state.level,
		reason = progress.REASON_COMPLETED,
	}
end

--- Checks a result reported by a module.
-- @return true  or  nil, error message
function progress.check_result(module, level, task_id)
	if type(level) ~= "number" or level ~= math.floor(level)
			or level < 1 or level > #module.levels then
		return nil, "module '" .. module.id .. "' has no level " .. tostring(level)
	end
	if not module.levels[level].by_id[task_id] then
		return nil, "level " .. level .. " of '" .. module.id
			.. "' has no task type '" .. tostring(task_id) .. "'"
	end
	return true
end

--- Records a result.
-- Only solved tasks on the player's current level count for the workload.
-- @param result Table with level, task and solved.
-- @return new state, list of events, true if the result counted
function progress.record(module, state, result)
	assert(progress.check_result(module, result.level, result.task))
	local new_state = copy_state(state)
	local events = {}

	if result.solved ~= true or result.level ~= new_state.level then
		return new_state, events, false
	end

	local level = new_state.level
	local task = module.levels[level].by_id[result.task]
	local counts = new_state.solved[level] or {}
	new_state.solved[level] = counts
	if (counts[task.id] or 0) >= task.required then
		return new_state, events, false
	end
	counts[task.id] = (counts[task.id] or 0) + 1

	local done, total = progress.done_tasks(module, new_state, level)
	if done == total and not new_state.completed[level] then
		new_state.completed[level] = true
		events[#events + 1] = {
			name = progress.LEVEL_COMPLETED,
			level = level,
			stage = module.levels[level].stage,
		}
		if level == #module.levels then
			events[#events + 1] = { name = progress.MODULE_COMPLETED }
		end
		move_up(module, new_state, events)
	end
	return new_state, events, true
end

--- Sets the level by hand. The counts of all levels are kept.
-- @return new state, list of events  or  nil, error message
function progress.set_level(module, state, level)
	if type(level) ~= "number" or level ~= math.floor(level)
			or level < 1 or level > #module.levels then
		return nil, "module '" .. module.id .. "' has levels 1 to " .. #module.levels
	end
	local new_state = copy_state(state)
	local events = {}
	if level ~= new_state.level then
		events[1] = {
			name = progress.LEVEL_CHANGED,
			old_level = new_state.level,
			new_level = level,
			reason = progress.REASON_TEACHER,
		}
		new_state.level = level
	end
	return new_state, events
end

--- Locks or unlocks moving up after completing a level. Unlocking moves
-- a player up who has completed their level in the meantime.
-- @return new state, list of events
function progress.set_locked(module, state, locked)
	local new_state = copy_state(state)
	local events = {}
	new_state.locked = locked == true
	move_up(module, new_state, events)
	return new_state, events
end

return progress
