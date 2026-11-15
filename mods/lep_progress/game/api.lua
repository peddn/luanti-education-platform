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
			dispatcher:emit("level_completed", player_name, module.id, event.level)
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

--- Returns id, title and number of levels of a module, or nil.
function lep_progress.get_module(module_id)
	local module = modules:get(module_id)
	if not module then
		return nil
	end
	return { id = module.id, title = module.title, levels = #module.levels }
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

	local state = get_state(result.player, module)
	local new_state, events, counted = progress.record(module, state, {
		level = result.level,
		task = result.task,
		solved = result.solved == true,
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

--- Registers a function(result) called for every reported task. The
-- result has the fields of lep_progress.report, plus player_level and
-- counted.
lep_progress.register_on_result = dispatcher:registrar("result")

--- Registers a function(player_name, module_id, level) called when a
-- player completes a level.
lep_progress.register_on_level_completed = dispatcher:registrar("level_completed")

--- Registers a function(player_name, module_id, old_level, new_level,
-- reason) called when the level of a player changes. Reason is
-- lep_progress.REASON_COMPLETED or lep_progress.REASON_TEACHER.
lep_progress.register_on_level_changed = dispatcher:registrar("level_changed")

--- Registers a function(player_name, module_id) called when a player
-- completes the last level of a module.
lep_progress.register_on_module_completed = dispatcher:registrar("module_completed")
