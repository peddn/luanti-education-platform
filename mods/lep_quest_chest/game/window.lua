-- The window of a task chest: question, input field, reward.
--
-- Task and solution stay on the server. The window only carries the text
-- of the question, and what a client sends back is checked again: is the
-- chest still there, does the player stand next to it, may they answer.

local load = lep_core.loader("lep_quest_chest")
local chests = load("src/chests")
local world = load("game/chests")
local S = core.get_translator("lep_quest_chest")
local formspec = lep_core.formspec

local FORM = "lep_quest_chest:window"
-- Longest answer that is looked at.
local MAX_INPUT = 32

local store = world.store
local attempts = chests.new_attempts()

-- Per player: the chest whose window is open, as { pos, run }. `run`
-- counts up with every window, so late timers notice they are outdated.
local open = {}
local runs = 0

local function close(player_name)
	if open[player_name] then
		open[player_name] = nil
		core.close_formspec(player_name, FORM)
	end
end

local show

-- The lines other mods have to say about the task, such as the reward.
local function info_lines(player_name, task)
	return lep_progress.get_task_info(player_name, task.module, task.level, task.task,
		lep_progress.KIND_DAILY)
end

show = function(player_name, pos)
	local now = os.time()
	local may_manage = lep_quest_chest.may_manage(player_name)
	local pad = formspec.PADDING
	local width = 9
	local top = formspec.CONTENT_TOP
	local fs = formspec.new(width, top + 4.5)
		:title(S("Task chest"))

	runs = runs + 1
	local run = runs
	open[player_name] = { pos = pos, run = run }

	local wait = attempts:wait_left(player_name, pos, now)
	if store:has_solved(pos, player_name) then
		fs:label(pad, top + 0.25, S("You have already solved this chest."))
	elseif wait > 0 then
		fs:label(pad, top + 0.25, S("That was wrong."))
		fs:label(pad, top + 0.85, S("You get a new task in @1 seconds.", wait))
		-- Show the new task by itself when the time is up.
		core.after(wait + 0.2, function()
			local current = open[player_name]
			if current and current.run == run and store:has(pos) then
				show(player_name, pos)
			end
		end)
	else
		local task = attempts:get_task(player_name, pos)
		if not task then
			task = lep_progress.get_short_task(player_name)
			if task then
				attempts:set_task(player_name, pos, task)
			end
		end
		if task then
			fs:big_label(pad, top + 0.3, task.text)
			fs:field(pad, top + 0.9, 4.5, 0.8, "answer", "", "")
			fs:submit_on_enter("answer")
			fs:button(pad + 4.75, top + 0.9, width - 2 * pad - 4.75, 0.8, "check", S("Check"))
			for index, line in ipairs(info_lines(player_name, task)) do
				fs:label(pad, top + 2.2 + (index - 1) * 0.5, line)
			end
		else
			fs:label(pad, top + 0.25, S("There are no tasks at the moment."))
		end
	end

	if may_manage then
		fs:button_exit(pad, top + 4.5 - pad - 0.8, width - 3 * pad - formspec.CLOSE_WIDTH, 0.8,
			"remove", S("Remove this chest"))
	end
	fs:close(S("Close"))
	core.show_formspec(player_name, FORM, fs:build())
end

world.set_on_rightclick(function(player_name, pos)
	if not store:has(pos) then
		-- A chest the list does not know: it is about to be removed.
		return
	end
	-- No window when there is nothing to type or to press.
	if store:has_solved(pos, player_name) and not lep_quest_chest.may_manage(player_name) then
		core.chat_send_player(player_name, S("You have already solved this chest."))
		return
	end
	show(player_name, pos)
end)

world.set_on_removed(function(pos)
	attempts:forget_chest(pos)
	for player_name, current in pairs(open) do
		if vector.equals(current.pos, pos) then
			close(player_name)
		end
	end
end)

local function answer(player_name, pos, text)
	local now = os.time()
	local task = attempts:get_task(player_name, pos)
	if store:has_solved(pos, player_name) or attempts:wait_left(player_name, pos, now) > 0
			or not task then
		show(player_name, pos)
		return
	end
	text = tostring(text or ""):sub(1, MAX_INPUT):gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then
		show(player_name, pos)
		return
	end

	local ok, solved = pcall(task.check, text)
	if not ok then
		core.log("error", "[lep_quest_chest] checking a task of " .. task.module
			.. " failed: " .. tostring(solved))
		solved = false
	end
	solved = solved == true
	local tries = attempts:tries(player_name, pos) + 1

	if solved then
		store:mark_solved(pos, player_name, now)
		world.save()
		attempts:set_task(player_name, pos, nil)
		close(player_name)
		core.chat_send_player(player_name, S("Right!"))
	else
		attempts:fail(player_name, pos, now)
		show(player_name, pos)
	end
	lep_progress.play_feedback(player_name, solved)

	-- A task chest is a daily task of normal effort. What that earns is
	-- not decided here.
	local reported, err = lep_progress.report({
		player = player_name,
		module = task.module,
		task = task.task,
		level = task.level,
		solved = solved,
		kind = lep_progress.KIND_DAILY,
		effort = lep_progress.EFFORT_NORMAL,
		attempts = tries,
	})
	if not reported then
		core.log("error", "[lep_quest_chest] report failed: " .. tostring(err))
	end
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= FORM then
		return false
	end
	local player_name = player:get_player_name()
	local current = open[player_name]
	if not current then
		return true
	end
	local pos = current.pos
	local wants_remove = fields.remove ~= nil
	if fields.quit and not wants_remove then
		open[player_name] = nil
		return true
	end

	-- The client says which button was pressed. Everything else is checked
	-- here again.
	if not store:has(pos) or not chests.in_reach(player:get_pos(), pos) then
		close(player_name)
		return true
	end
	if wants_remove then
		open[player_name] = nil
		if lep_quest_chest.may_manage(player_name) then
			lep_quest_chest.remove(pos)
			core.log("action", "[lep_quest_chest] " .. player_name .. " removed the chest at "
				.. core.pos_to_string(pos))
		end
		return true
	end
	if fields.check or fields.key_enter_field == "answer" then
		answer(player_name, pos, fields.answer)
	end
	return true
end)

core.register_on_leaveplayer(function(player)
	open[player:get_player_name()] = nil
end)
