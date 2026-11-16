-- Chat commands and messages. The commands for teachers are a stopgap
-- until the web application exists.

local S = core.get_translator("lep_progress")

core.register_privilege("lep_set_level", {
	description = "Can set the level of players in learning modules",
	give_to_singleplayer = false,
	give_to_admin = true,
})

core.register_privilege("lep_view_progress", {
	description = "Can view the learning progress of other players",
	give_to_singleplayer = false,
	give_to_admin = true,
})

local function module_title(module_id)
	local module = lep_progress.get_module(module_id)
	return module and module.title or module_id
end

-- Tell players what happened to their level.
lep_progress.register_on_level_completed(function(player_name, module_id, level)
	if core.get_player_by_name(player_name) then
		core.chat_send_player(player_name,
			S("You completed level @1 of @2.", level, module_title(module_id)))
	end
end)

lep_progress.register_on_level_changed(function(player_name, module_id, _, new_level)
	if core.get_player_by_name(player_name) then
		core.chat_send_player(player_name,
			S("You are now on level @1 of @2.", new_level, module_title(module_id)))
	end
end)

lep_progress.register_on_module_completed(function(player_name, module_id)
	if core.get_player_by_name(player_name) then
		core.chat_send_player(player_name,
			S("You completed all levels of @1.", module_title(module_id)))
	end
end)

local function describe(player_name)
	local lines = {}
	for _, module_id in ipairs(lep_progress.get_module_ids()) do
		local info = lep_progress.get_progress(player_name, module_id)
		local line = S("@1: level @2 of @3, @4 %", info.title, info.level, info.levels,
			info.percent)
		if info.completed then
			line = line .. " " .. S("(module completed)")
		end
		if info.locked then
			line = line .. " " .. S("(moving up is locked)")
		end
		lines[#lines + 1] = line
		for _, task in ipairs(info.tasks) do
			lines[#lines + 1] = "  " .. S("@1: @2 of @3", task.title, task.solved,
				task.required)
		end
	end
	if #lines == 0 then
		return S("There are no learning modules yet.")
	end
	return table.concat(lines, "\n")
end

core.register_chatcommand("lep_progress", {
	params = "[<player>]",
	description = S("Show your learning progress, or that of another player"),
	func = function(name, param)
		local target = param:match("^%s*(%S+)")
		if target and target ~= name then
			if not core.check_player_privs(name, { lep_view_progress = true }) then
				return false, S("You may only view your own progress.")
			end
			if not core.player_exists(target) then
				return false, S("There is no player @1.", target)
			end
			return true, S("Progress of @1:", target) .. "\n" .. describe(target)
		end
		return true, describe(name)
	end,
})

-- Reads "<player> <module> <rest>" and checks player and module.
local function parse_target(param)
	local target, module_id, rest = param:match("^%s*(%S+)%s+(%S+)%s+(%S+)%s*$")
	if not target then
		return nil
	end
	if not core.player_exists(target) then
		return false, S("There is no player @1.", target)
	end
	if not lep_progress.get_module(module_id) then
		return false, S("There is no module @1. Modules: @2", module_id,
			table.concat(lep_progress.get_module_ids(), ", "))
	end
	return target, module_id, rest
end

core.register_chatcommand("lep_level", {
	params = "<player> <module> <level>",
	description = S("Set the level of a player in a learning module"),
	privs = { lep_set_level = true },
	func = function(_, param)
		local target, module_id, rest = parse_target(param)
		if target == nil then
			return false, S("Usage: /lep_level <player> <module> <level>")
		elseif target == false then
			return false, module_id
		end
		local info = lep_progress.get_progress(target, module_id)
		local level = tonumber(rest)
		if not level or not lep_progress.set_level(target, module_id, level) then
			return false, S("@1 has the levels 1 to @2.", info.title, info.levels)
		end
		return true, S("@1 is now on level @2 of @3.", target, level, info.title)
	end,
})

core.register_chatcommand("lep_level_lock", {
	params = "<player> <module> on | off",
	description = S("Lock or unlock moving up after a completed level"),
	privs = { lep_set_level = true },
	func = function(_, param)
		local target, module_id, rest = parse_target(param)
		if target == nil or (target and rest ~= "on" and rest ~= "off") then
			return false, S("Usage: /lep_level_lock <player> <module> on | off")
		elseif target == false then
			return false, module_id
		end
		lep_progress.set_locked(target, module_id, rest == "on")
		local title = lep_progress.get_progress(target, module_id).title
		if rest == "on" then
			return true, S("@1 no longer moves up automatically in @2.", target, title)
		end
		return true, S("@1 moves up automatically in @2 again.", target, title)
	end,
})
