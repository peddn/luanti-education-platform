-- Debug helpers. Only loaded when the setting "lep_debug" is true.
--
-- A test module and a command to report results, so progress can be tried
-- before the first real learning module exists.

if not core.registered_privileges.lep_debug then
	core.register_privilege("lep_debug", {
		description = "Can use LEP debug commands",
		give_to_singleplayer = false,
	})
end

local MODULE = "lep_progress:debug"

lep_progress.register_module(MODULE, {
	title = "Testmodul",
	levels = {
		{ tasks = {
			{ id = "a1", title = "Aufgabe A1", required = 2 },
			{ id = "a2", title = "Aufgabe A2", required = 2 },
		} },
		{ stage = true, tasks = {
			{ id = "b1", title = "Aufgabe B1", required = 2 },
			{ id = "b2", title = "Aufgabe B2", required = 1 },
		} },
		{ tasks = { { id = "c1", title = "Aufgabe C1", required = 2 } } },
		{ tasks = { { id = "d1", title = "Aufgabe D1", required = 1 } } },
	},
})

lep_progress.register_on_result(function(result)
	core.log("action", "[lep_progress] result: " .. result.player .. " " .. result.module
		.. " " .. result.task .. " level " .. result.level
		.. (result.solved and " solved" or " failed")
		.. (result.counted and ", counted" or ", not counted"))
end)

core.register_chatcommand("lep_report", {
	params = "<task> [fail | chest] [<level>]",
	description = "Report a task of the test module as solved, as failed, or as "
		.. "solved in a task chest. Without a level, your current level is used.",
	privs = { lep_debug = true },
	func = function(name, param)
		local task, second, third = param:match("^%s*(%S+)%s*(%S*)%s*(%S*)")
		if not task then
			return false, "Usage: /lep_report <task> [fail | chest] [<level>]"
		end
		local failed = second == "fail"
		local from_chest = second == "chest"
		local level = tonumber((failed or from_chest) and third or second)
			or lep_progress.get_level(name, MODULE)
		local ok, err = lep_progress.report({
			player = name,
			module = MODULE,
			task = task,
			level = level,
			solved = not failed,
			kind = from_chest and lep_progress.KIND_CHEST or lep_progress.KIND_TASK,
			attempts = 1,
		})
		if not ok then
			return false, "Report failed: " .. tostring(err)
		end
		local info = lep_progress.get_progress(name, MODULE)
		return true, "Reported. Level " .. info.level .. " of " .. info.levels
			.. ", " .. info.percent .. " %"
	end,
})
