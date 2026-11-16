-- Offers mental arithmetic as short tasks, for the task chest.

local load = lep_core.loader("lep_math")
local tasks = load("src/tasks")
local answer = load("src/answer")

-- A task of the player's own level, of any of its task types.
lep_progress.register_short_tasks(lep_math.MODULE, function(player_name)
	local info = lep_progress.get_progress(player_name, lep_math.MODULE)
	local entry = info.tasks[math.random(1, #info.tasks)]
	local task = tasks.generate(entry.id, math.random)
	return {
		text = tasks.readable(task.text),
		task = entry.id,
		level = info.level,
		-- The solution stays in here, on the server.
		check = function(input)
			return answer.is_correct(input, task.answer)
		end,
	}
end)
