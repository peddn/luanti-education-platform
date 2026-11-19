-- Trophies for milestones in the learning modules.

local load = lep_core.loader("lep_trophies")
local trophies = load("src/trophies")
local S = core.get_translator("lep_trophies")

-- The modules are known once all mods are loaded.
core.register_on_mods_loaded(function()
	for _, module_id in ipairs(lep_progress.get_module_ids()) do
		local module = lep_progress.get_module(module_id)

		-- The last level is never a stage: it completes the module, and
		-- that has its own trophy.
		for index, level in ipairs(module.stages) do
			lep_trophies.register_trophy(trophies.stage_id(module_id, level), {
				title = S("@1: stage @2", module.title, index),
				description = S("Completed level @1 of @2.", level, module.title),
				material = trophies.STAGE_MATERIAL,
			})
		end
		lep_trophies.register_trophy(trophies.module_id(module_id), {
			title = S("@1: completed", module.title),
			description = S("Completed all levels of @1.", module.title),
			material = trophies.MODULE_MATERIAL,
		})

		for _, step in ipairs(trophies.TASK_STEPS) do
			lep_trophies.register_trophy(trophies.tasks_id(module_id, step.count), {
				title = S("@1: @2 tasks", module.title, step.count),
				description = S("Solved @1 level tasks in @2.", step.count, module.title),
				material = step.material,
			})
		end
	end

	for _, step in ipairs(trophies.DAILY_STEPS) do
		lep_trophies.register_trophy(trophies.daily_id(step.count), {
			title = S("@1 daily tasks", step.count),
			description = S("Solved @1 daily tasks.", step.count),
			material = step.material,
		})
	end
end)

--- Adds to a counter of a player and awards the trophies it reaches.
-- For the files of this mod only.
function lep_trophies._count(player_name, counter, amount, steps, id_for)
	local state, old, new = trophies.count(
		lep_trophies._get_state(player_name), counter, amount)
	lep_trophies._set_state(player_name, state)
	for _, step in ipairs(trophies.steps_reached(steps, old, new)) do
		lep_trophies.award(player_name, id_for(step.count))
	end
end

lep_progress.register_on_level_completed(function(player_name, module_id, level, is_stage)
	if is_stage then
		lep_trophies.award(player_name, trophies.stage_id(module_id, level))
	end
end)

lep_progress.register_on_module_completed(function(player_name, module_id)
	lep_trophies.award(player_name, trophies.module_id(module_id))
end)

-- Who completed a module before it had a trophy of its own gets it now.
-- Back then the last level counted as a stage; that trophy is gone.
core.register_on_mods_loaded(function()
	core.after(0, function()
		for _, player_name in ipairs(lep_progress.get_players()) do
			for _, module_id in ipairs(lep_progress.get_module_ids()) do
				local info = lep_progress.get_progress(player_name, module_id)
				local id = trophies.module_id(module_id)
				if info and info.completed and not lep_trophies.has(player_name, id) then
					lep_trophies.award(player_name, id)
				end
			end
		end
	end)
end)

-- Every solved task counts, also one that earns no reward any more.
-- Practice is worth a trophy.
lep_progress.register_on_result(function(result)
	if not result.solved then
		return
	end
	if result.kind == lep_progress.KIND_DAILY then
		lep_trophies._count(result.player, trophies.DAILY_COUNTER, 1,
			trophies.DAILY_STEPS, trophies.daily_id)
	else
		lep_trophies._count(result.player, trophies.tasks_counter(result.module), 1,
			trophies.TASK_STEPS, function(count)
				return trophies.tasks_id(result.module, count)
			end)
	end
end)

--- Returns the milestones a player has not reached yet, each with title,
-- count and target. For the command that lists trophies.
function lep_trophies._open_counters(player_name)
	local counters = lep_trophies._get_state(player_name).counters
	local open = {}
	local function add(steps, counter, id_for)
		local count = counters[counter] or 0
		for _, step in ipairs(steps) do
			if count < step.count then
				open[#open + 1] = {
					title = lep_trophies.get_trophy(id_for(step.count)).title,
					count = count,
					target = step.count,
				}
				return
			end
		end
	end
	for _, module_id in ipairs(lep_progress.get_module_ids()) do
		add(trophies.TASK_STEPS, trophies.tasks_counter(module_id), function(count)
			return trophies.tasks_id(module_id, count)
		end)
	end
	add(trophies.DAILY_STEPS, trophies.DAILY_COUNTER, trophies.daily_id)
	return open
end
