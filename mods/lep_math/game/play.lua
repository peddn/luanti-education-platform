-- Playing: tasks, key presses, feedback and the line at the top of the
-- screen.

local load = lep_core.loader("lep_math")
local tasks = load("src/tasks")
local answer = load("src/answer")
local session = load("src/session")
local S = core.get_translator("lep_math")

-- Seconds the display stays green or red.
local FLASH = 0.8
-- Seconds the solution is shown after two wrong answers.
local SOLUTION = 2.5

-- Per player: state (see src/session.lua), started (time of the task),
-- busy (true while the display shows feedback), run (counts up with every
-- task, so late timers notice that they are outdated), hud ids.
local sessions = {}

local function in_own_room(player_name)
	local type_id, owner = lep_rooms.get_current_room(player_name)
	return type_id == lep_math.ROOM_TYPE and owner == player_name
end

local function extra_keys(task)
	return { comma = task.answer ~= math.floor(task.answer), minus = task.answer < 0 }
end

--------------------------------------------------------------------------
-- Line at the top of the screen

local function update_hud(player_name)
	local player = core.get_player_by_name(player_name)
	local current = sessions[player_name]
	if not player or not current then
		return
	end
	local info = lep_progress.get_progress(player_name, lep_math.MODULE)
	local task_type = current.state.task.type
	local first = S("@1, level @2 of @3", info.title, info.level, info.levels)
	for _, entry in ipairs(info.tasks) do
		if entry.id == task_type then
			first = first .. "   " .. S("@1: @2 of @3", entry.title, entry.solved, entry.required)
		end
	end
	local second = table.concat(lep_progress.get_task_info(
		player_name, lep_math.MODULE, tasks.get(task_type).level, task_type), "   ")

	local texts = { first, second }
	current.hud = current.hud or {}
	for index, text in ipairs(texts) do
		if current.hud[index] then
			player:hud_change(current.hud[index], "text", text)
		else
			current.hud[index] = player:hud_add({
				type = "text",
				position = { x = 0.5, y = 0.06 },
				offset = { x = 0, y = (index - 1) * 24 },
				alignment = { x = 0, y = 0 },
				number = index == 1 and 0xFFFFFF or 0xFFD060,
				text = text,
			})
		end
	end
end

local function remove_hud(player_name)
	local player = core.get_player_by_name(player_name)
	local current = sessions[player_name]
	if player and current and current.hud then
		for _, id in pairs(current.hud) do
			player:hud_remove(id)
		end
	end
end

--------------------------------------------------------------------------
-- Tasks

local function show(player_name, input, colour)
	local task = sessions[player_name].state.task
	lep_math._show(player_name, task.text, input, colour, extra_keys(task))
end

local function start_task(player_name)
	local info = lep_progress.get_progress(player_name, lep_math.MODULE)
	local current = sessions[player_name] or { run = 0 }
	-- Not the same task twice in a row, if chance allows.
	local previous = current.state and current.state.task.text
	local task
	for _ = 1, 4 do
		task = tasks.generate(tasks.choose(info.tasks, math.random), math.random)
		if task.text ~= previous then
			break
		end
	end
	current.state = session.new(task)
	current.started = core.get_us_time()
	current.busy = false
	current.run = current.run + 1
	sessions[player_name] = current
	show(player_name, "", lep_math.NORMAL)
	update_hud(player_name)
end

local function stop(player_name)
	remove_hud(player_name)
	sessions[player_name] = nil
end

-- Calls action after a delay, unless the player has moved on to another
-- task or left in the meantime.
local function later(player_name, seconds, action)
	local run = sessions[player_name].run
	core.after(seconds, function()
		local current = sessions[player_name]
		if current and current.run == run and in_own_room(player_name) then
			action()
		end
	end)
end

local function report(player_name, current, solved)
	local task = current.state.task
	lep_progress.report({
		player = player_name,
		module = lep_math.MODULE,
		task = task.type,
		level = tasks.get(task.type).level,
		solved = solved,
		attempts = current.state.attempts,
		duration = math.floor((core.get_us_time() - current.started) / 1000000),
	})
end

--- Called by the key nodes.
function lep_math._on_key(player, key)
	local player_name = player:get_player_name()
	-- The keys only work for the owner standing in their own room.
	if not in_own_room(player_name) then
		return
	end
	if not sessions[player_name] then
		start_task(player_name)
	end
	local current = sessions[player_name]
	if current.busy then
		return
	end

	local typed = current.state.input
	local state, what = session.press(current.state, key, answer.is_correct)
	current.state = state

	if what == session.TYPED then
		core.sound_play("lep_math_key", { to_player = player_name, gain = 0.5 }, true)
		show(player_name, state.input, lep_math.NORMAL)

	elseif what == session.CORRECT then
		current.busy = true
		core.sound_play("lep_math_right", { to_player = player_name }, true)
		show(player_name, typed, lep_math.RIGHT)
		report(player_name, current, true)
		later(player_name, FLASH, function()
			start_task(player_name)
		end)

	elseif what == session.WRONG then
		current.busy = true
		core.sound_play("lep_math_wrong", { to_player = player_name }, true)
		show(player_name, typed, lep_math.WRONG)
		later(player_name, FLASH, function()
			current.busy = false
			show(player_name, "", lep_math.NORMAL)
		end)

	elseif what == session.REVEALED then
		current.busy = true
		core.sound_play("lep_math_wrong", { to_player = player_name }, true)
		show(player_name, typed, lep_math.WRONG)
		report(player_name, current, false)
		later(player_name, FLASH, function()
			-- Show what would have been right, then go on.
			show(player_name, answer.format(state.task.answer), lep_math.RIGHT)
			later(player_name, SOLUTION, function()
				start_task(player_name)
			end)
		end)
	end
end

--------------------------------------------------------------------------
-- Coming and going

local function arrive(player_name)
	local player = core.get_player_by_name(player_name)
	if player and lep_places.get_place(player_name) == lep_math.PLACE then
		start_task(player_name)
	end
end

lep_places.register_on_place_changed(function(player_name, old_place, new_place)
	if new_place == lep_math.PLACE then
		local player = core.get_player_by_name(player_name)
		if player then
			-- Look at the display.
			player:set_look_horizontal(0)
			player:set_look_vertical(0)
		end
		arrive(player_name)
	elseif old_place == lep_math.PLACE then
		stop(player_name)
	end
end)

-- A player who logged out in the room comes back there.
core.register_on_joinplayer(function(player)
	local player_name = player:get_player_name()
	core.after(1, function()
		arrive(player_name)
	end)
end)

core.register_on_leaveplayer(function(player)
	sessions[player:get_player_name()] = nil
end)

-- A rebuilt room has an empty display.
lep_rooms.register_on_room_built(function(owner, type_id)
	if type_id == lep_math.ROOM_TYPE and sessions[owner] then
		start_task(owner)
	end
end)

-- The teacher changed the level: the next task comes from the new one.
lep_progress.register_on_level_changed(function(player_name, module_id, _, _, reason)
	local current = sessions[player_name]
	if module_id == lep_math.MODULE and current and not current.busy
			and reason == lep_progress.REASON_TEACHER then
		start_task(player_name)
	end
end)
