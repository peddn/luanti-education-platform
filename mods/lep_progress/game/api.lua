-- Public API of lep_progress.

local load = lep_core.loader("lep_progress")
local progress = load("src/progress")
local storage = load("game/storage")

local modules = progress.new_modules()

local dispatcher = lep_core.events.new(function(event_name, err)
	core.log("error", "[lep_progress] callback for " .. event_name .. " failed: "
		.. tostring(err))
end)

local function get_state(player_name, module)
	return progress.normalize(module, storage.load(player_name)[module.id])
end

local function emit(player_name, module, events)
	for _, event in ipairs(events) do
		if event.name == progress.LEVEL_COMPLETED then
			dispatcher:emit("level_completed", player_name, module.id, event.level,
				event.stage)
		elseif event.name == progress.LEVEL_CHANGED then
			dispatcher:emit("level_changed", player_name, module.id,
				event.old_level, event.new_level, event.reason)
		elseif event.name == progress.MODULE_COMPLETED then
			dispatcher:emit("module_completed", player_name, module.id)
		end
	end
end

local function check_player(player_name)
	if type(player_name) ~= "string" or player_name == "" then
		return false, "player name must be a non-empty string"
	end
	return true
end

lep_progress.KIND_TASK = progress.KIND_TASK
lep_progress.KIND_DAILY = progress.KIND_DAILY
lep_progress.EFFORT_LOW = progress.EFFORT_LOW
lep_progress.EFFORT_NORMAL = progress.EFFORT_NORMAL
lep_progress.EFFORT_HIGH = progress.EFFORT_HIGH
lep_progress.REASON_COMPLETED = progress.REASON_COMPLETED
lep_progress.REASON_TEACHER = progress.REASON_TEACHER

--- Registers a learning module with its levels and task types.
-- A module can have any number of levels. See src/progress.lua for the
-- definition table.
function lep_progress.register_module(module_id, def)
	modules:register(module_id, def)
	core.log("action", "[lep_progress] registered module " .. module_id
		.. " with " .. #def.levels .. " levels")
end

--- Returns the ids of all modules in the order they were registered.
function lep_progress.get_module_ids()
	return modules:ids()
end

--- Returns id, title, number of levels and the list of levels that end a
-- stage of a module, or nil.
function lep_progress.get_module(module_id)
	local module = modules:get(module_id)
	if not module then
		return nil
	end
	local stages = {}
	for number, level in ipairs(module.levels) do
		if level.stage then
			stages[#stages + 1] = number
		end
	end
	return { id = module.id, title = module.title, levels = #module.levels, stages = stages }
end

--- Returns the level a player is on in a module, or nil for an unknown
-- module. Players who never played start on level 1.
function lep_progress.get_level(player_name, module_id)
	local module = modules:get(module_id)
	if not module or not check_player(player_name) then
		return nil
	end
	return get_state(player_name, module).level
end

--- Returns how far a player is in a module, or nil for an unknown module:
--   module_id, title
--   level           current level
--   levels          number of levels of the module
--   percent         share of done task types of the current level
--   locked          true if moving up is locked
--   level_completed true if the current level is completed
--   completed       true if the whole module is completed
--   tasks           task types of the current level, each with id, title,
--                   solved and required
function lep_progress.get_progress(player_name, module_id)
	local module = modules:get(module_id)
	if not module or not check_player(player_name) then
		return nil
	end
	local state = get_state(player_name, module)
	local tasks = {}
	for index, task in ipairs(module.levels[state.level].tasks) do
		tasks[index] = {
			id = task.id,
			title = task.title,
			solved = progress.solved_count(state, state.level, task.id),
			required = task.required,
		}
	end
	return {
		module_id = module.id,
		title = module.title,
		level = state.level,
		levels = #module.levels,
		percent = progress.percent(module, state, state.level),
		locked = state.locked,
		level_completed = state.completed[state.level] == true,
		completed = progress.is_module_completed(module, state),
		tasks = tasks,
	}
end

--- Reports what happened in a task. Modules call this and decide nothing
-- themselves.
-- @param result Table with:
--   player    account name
--   module    module id
--   task      id of the task type
--   level     level the task belongs to
--   solved    true or false
--   kind      optional: lep_progress.KIND_TASK (default) for a task of the
--             level's workload, lep_progress.KIND_DAILY for a daily task,
--             for example from a task chest. Daily tasks can be repeated
--             every day and never count for the workload.
--   effort    optional, for daily tasks: lep_progress.EFFORT_LOW,
--             EFFORT_NORMAL (default) or EFFORT_HIGH
--   attempts, hints, duration   optional numbers, passed on unchanged
-- @return true  or  false, error message
function lep_progress.report(result)
	if type(result) ~= "table" then
		return false, "result must be a table"
	end
	local ok, err = check_player(result.player)
	if not ok then
		return false, err
	end
	local module = modules:get(result.module)
	if not module then
		return false, "unknown module '" .. tostring(result.module) .. "'"
	end
	ok, err = progress.check_result(module, result.level, result.task)
	if not ok then
		return false, err
	end

	local kind = result.kind or progress.KIND_TASK
	if kind ~= progress.KIND_TASK and kind ~= progress.KIND_DAILY then
		return false, "unknown kind '" .. tostring(kind) .. "'"
	end
	local effort = result.effort or progress.EFFORT_NORMAL
	if effort ~= progress.EFFORT_LOW and effort ~= progress.EFFORT_NORMAL
			and effort ~= progress.EFFORT_HIGH then
		return false, "unknown effort '" .. tostring(effort) .. "'"
	end

	local state = get_state(result.player, module)
	local new_state, events, counted = progress.record(module, state, {
		level = result.level,
		task = result.task,
		solved = result.solved == true,
		kind = kind,
	})
	if counted then
		storage.save(result.player, module.id, new_state)
	end

	dispatcher:emit("result", {
		player = result.player,
		module = module.id,
		task = result.task,
		level = result.level,
		solved = result.solved == true,
		kind = kind,
		effort = effort,
		attempts = result.attempts,
		hints = result.hints,
		duration = result.duration,
		-- Level of the player when the task was reported.
		player_level = state.level,
		-- True if the task counted for the workload.
		counted = counted,
	})
	emit(result.player, module, events)
	return true
end

--- Sets the level of a player in a module by hand.
-- @return true  or  false, error message
function lep_progress.set_level(player_name, module_id, level)
	local ok, err = check_player(player_name)
	if not ok then
		return false, err
	end
	local module = modules:get(module_id)
	if not module then
		return false, "unknown module '" .. tostring(module_id) .. "'"
	end
	local new_state, events = progress.set_level(module, get_state(player_name, module), level)
	if not new_state then
		return false, events
	end
	storage.save(player_name, module.id, new_state)
	emit(player_name, module, events)
	return true
end

--- Locks or unlocks moving up after a completed level.
-- @return true  or  false, error message
function lep_progress.set_locked(player_name, module_id, locked)
	local ok, err = check_player(player_name)
	if not ok then
		return false, err
	end
	local module = modules:get(module_id)
	if not module then
		return false, "unknown module '" .. tostring(module_id) .. "'"
	end
	local new_state, events = progress.set_locked(
		module, get_state(player_name, module), locked)
	storage.save(player_name, module.id, new_state)
	emit(player_name, module, events)
	return true
end

-- How loud the feedback sounds are played. The files are recorded at
-- full volume.
local FEEDBACK_GAIN = 0.5

--- Plays the sound for a right or a wrong answer to one player. All
-- learning modules use this, so an answer sounds the same everywhere. The
-- module decides the moment, for example together with its own feedback
-- on screen.
function lep_progress.play_feedback(player_name, solved)
	core.sound_play(solved and "lep_progress_right" or "lep_progress_wrong",
		{ to_player = player_name, gain = FEEDBACK_GAIN }, true)
end

local task_info_providers = {}

--- Registers a function(player_name, module_id, level, task_id, kind)
-- that returns a line of text about a task a player is about to solve, or
-- nil. Learning modules show these lines without knowing where they come
-- from: this is how the reward becomes visible before the task, although
-- a module knows nothing about rewards.
function lep_progress.register_task_info(provider)
	assert(type(provider) == "function", "register_task_info: provider must be a function")
	task_info_providers[#task_info_providers + 1] = provider
end

--- Returns the lines of text that other mods have to say about a task,
-- as a list. `kind` is lep_progress.KIND_TASK by default.
function lep_progress.get_task_info(player_name, module_id, level, task_id, kind)
	local lines = {}
	for _, provider in ipairs(task_info_providers) do
		local ok, line = pcall(provider, player_name, module_id, level, task_id,
			kind or progress.KIND_TASK)
		if not ok then
			core.log("error", "[lep_progress] task info provider failed: " .. tostring(line))
		elseif type(line) == "string" and line ~= "" then
			lines[#lines + 1] = line
		end
	end
	return lines
end

--- Registers a function(result) called for every reported task. The
-- result has the fields of lep_progress.report, plus player_level and
-- counted.
lep_progress.register_on_result = dispatcher:registrar("result")

--- Registers a function(player_name, module_id, level, is_stage) called
-- when a player completes a level. is_stage is true if the level ends a
-- stage of the module.
lep_progress.register_on_level_completed = dispatcher:registrar("level_completed")

--- Registers a function(player_name, module_id, old_level, new_level,
-- reason) called when the level of a player changes. Reason is
-- lep_progress.REASON_COMPLETED or lep_progress.REASON_TEACHER.
lep_progress.register_on_level_changed = dispatcher:registrar("level_changed")

--- Registers a function(player_name, module_id) called when a player
-- completes the last level of a module.
lep_progress.register_on_module_completed = dispatcher:registrar("module_completed")
