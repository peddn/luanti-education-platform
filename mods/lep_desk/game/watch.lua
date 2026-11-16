-- Watching: a teacher jumps to a student unseen and comes back later.

local load = lep_core.loader("lep_desk")
local watch = load("src/watch")
local S = core.get_translator("lep_desk")

local STORAGE_KEY = "watch"
local mod_storage = core.get_mod_storage()
local list = watch.new(core.deserialize(mod_storage:get_string(STORAGE_KEY)))

local function save()
	mod_storage:set_string(STORAGE_KEY, core.serialize(list:data()))
end

-- Per watching teacher while online: props and nametag as they were, the
-- id of the line on screen.
local hidden = {}
-- Teachers this file is moving right now, so the move is not taken for
-- one the teacher made on their own.
local moving = {}

-- What makes a player unseen: no figure, no name tag, no footsteps, and
-- nothing to point at. The figure is shrunk to nothing, because the
-- engine switches the property is_visible of players back on by itself.
local UNSEEN = {
	visual_size = { x = 0, y = 0, z = 0 },
	pointable = false,
	makes_footstep_sound = false,
}

local function hud_text(target)
	return S("You are watching @1 unseen.", target)
end

local function hide(player, target)
	local name = player:get_player_name()
	local state = hidden[name]
	if state then
		player:hud_change(state.hud, "text", hud_text(target))
		return
	end
	local props = player:get_properties()
	state = { props = {}, nametag = player:get_nametag_attributes() }
	for key in pairs(UNSEEN) do
		state.props[key] = props[key]
	end
	player:set_properties(UNSEEN)
	player:set_nametag_attributes({ color = { a = 0, r = 255, g = 255, b = 255 } })
	state.hud = player:hud_add({
		type = "text",
		-- At the bottom, above hearts and hotbar. The top of the screen
		-- belongs to the chat.
		position = { x = 0.5, y = 1 },
		offset = { x = 0, y = -150 },
		alignment = { x = 0, y = 0 },
		number = 0x80D0FF,
		text = hud_text(target),
	})
	hidden[name] = state
end

local function show(player)
	local name = player:get_player_name()
	local state = hidden[name]
	if not state then
		return
	end
	hidden[name] = nil
	player:set_properties(state.props)
	player:set_nametag_attributes({ color = state.nametag.color })
	player:hud_remove(state.hud)
end

local function move(name, place, pos)
	moving[name] = true
	local ok, err = lep_places.move(name, place, pos)
	moving[name] = nil
	return ok, err
end

--- Returns the name of the student a teacher is watching, or nil.
function lep_desk.get_watched(teacher_name)
	return list:get_target(teacher_name)
end

--- Lets an online teacher jump to an online student, unseen.
-- @return true  or  false, error message
function lep_desk.watch(teacher_name, student_name)
	local teacher = core.get_player_by_name(teacher_name)
	local student = core.get_player_by_name(student_name)
	if not teacher or not student then
		return false, "both players have to be online"
	end
	local origin = { place = lep_places.get_place(teacher_name), pos = teacher:get_pos() }
	local first = list:start(teacher_name, origin, student_name)
	save()
	-- Unseen before arriving.
	hide(teacher, student_name)
	local ok, err = move(teacher_name, lep_places.get_place(student_name), student:get_pos())
	if not ok then
		if first then
			list:stop(teacher_name)
			save()
			show(teacher)
		end
		return false, err
	end
	return true
end

--- Brings a watching teacher back to where they came from and makes
-- them visible again.
-- @return true, or false if the teacher was not watching
function lep_desk.stop_watching(teacher_name)
	local origin = list:stop(teacher_name)
	if not origin then
		return false
	end
	save()
	local teacher = core.get_player_by_name(teacher_name)
	if teacher then
		if not move(teacher_name, origin.place, origin.pos) then
			moving[teacher_name] = true
			lep_places.move_back(teacher_name)
			moving[teacher_name] = nil
		end
		show(teacher)
	end
	return true
end

-- A teacher who leaves the place on their own, through a portal or an
-- exit, is visible again. Nobody walks through the world unseen by
-- accident.
lep_places.register_on_place_changed(function(player_name)
	if moving[player_name] or not list:is_watching(player_name) then
		return
	end
	list:stop(player_name)
	save()
	local player = core.get_player_by_name(player_name)
	if player then
		show(player)
		core.chat_send_player(player_name, S("You are visible again."))
	end
end)

-- Being unseen ends with the session. A teacher who logged out while
-- watching comes back to where they were.
core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	if list:is_watching(name) then
		core.after(0.5, function()
			lep_desk.stop_watching(name)
		end)
	end
end)

core.register_on_leaveplayer(function(player)
	hidden[player:get_player_name()] = nil
end)

local GROUP = S("Watch")

lep_desk.register_action("lep_desk:watch", {
	title = S("Jump there"),
	privilege = lep_desk.PRIV_WATCH,
	single = true,
	group = GROUP,
	run = function(teacher_name, targets)
		local ok = lep_desk.watch(teacher_name, targets[1])
		if not ok then
			return S("That did not work.")
		end
		return S("You are watching @1 unseen.", targets[1])
	end,
})

lep_desk.register_action("lep_desk:watch_back", {
	title = S("Back"),
	privilege = lep_desk.PRIV_WATCH,
	needs_targets = false,
	group = GROUP,
	run = function(teacher_name)
		if lep_desk.stop_watching(teacher_name) then
			return S("You are back and visible again.")
		end
		return S("You are not watching anybody.")
	end,
})
