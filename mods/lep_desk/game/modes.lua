-- The class mode at the desk: a switch between leisure, self-study and
-- lesson for the whole world.

local load = lep_core.loader("lep_desk")
local modes = load("src/modes")
local S = core.get_translator("lep_desk")

-- Seconds between two looks for students who are in the closed
-- wilderness: after joining, after dying, or however they got there.
local SWEEP_INTERVAL = 3

lep_desk.PRIV_MODE = "lep_set_mode"

core.register_privilege(lep_desk.PRIV_MODE, {
	description = "Can switch the class mode at the teacher's desk",
	give_to_singleplayer = false,
	give_to_admin = true,
})

-- The mode lives in memory. After a restart of the server no teacher is
-- online, and without a teacher it is leisure.
local mode = modes.LEISURE

lep_desk.MODE_LEISURE = modes.LEISURE
lep_desk.MODE_SELF_STUDY = modes.SELF_STUDY
lep_desk.MODE_LESSON = modes.LESSON

--- Returns the class mode: lep_desk.MODE_LEISURE, MODE_SELF_STUDY or
-- MODE_LESSON.
function lep_desk.get_mode()
	return mode
end

local function kind_of(place_id)
	if place_id == lep_places.WILDERNESS then
		return modes.WILDERNESS
	elseif lep_places.is_learning_place(place_id) then
		return modes.LEARNING
	end
	return modes.LOBBY
end

local REFUSALS = {
	[modes.WILDERNESS_CLOSED] = S("The wilderness is closed at the moment."),
	[modes.NO_ENTERING] = S("During the lesson your teacher sends you into the learning rooms."),
	[modes.NO_LEAVING] = S("During the lesson you stay here until your teacher brings you back."),
}

-- The mode binds students in what they do on their own. Teachers move
-- freely.
lep_places.register_access_rule(function(player_name, from_place, to_place)
	if lep_desk.may_open(player_name) then
		return true
	end
	local allowed, reason = modes.allows(mode, kind_of(from_place), kind_of(to_place))
	if not allowed then
		return false, REFUSALS[reason]
	end
	return true
end)

-- Brings the students who are in the closed wilderness into the lobby.
-- The spot where they stood is remembered: the portal leads back there.
local function clear_wilderness()
	if modes.wilderness_open(mode) or not core.global_exists("lep_lobby") then
		return
	end
	for _, student in ipairs(lep_desk.get_students()) do
		local player = core.get_player_by_name(student)
		if lep_places.get_place(student) == lep_places.WILDERNESS and player:get_hp() > 0 then
			lep_places.set_return(student, lep_places.WILDERNESS, player:get_pos())
			lep_lobby.enter(student, function(ok)
				if ok then
					core.chat_send_player(student, S("The wilderness is closed at the moment. "
						.. "The portal will bring you back to where you were."))
				end
			end)
		end
	end
end

local ANNOUNCEMENTS = {
	[modes.LEISURE] = S("Leisure: the wilderness is open again."),
	[modes.SELF_STUDY] = S("Self-study: the wilderness is closed, the learning rooms are open."),
	[modes.LESSON] = S("Lesson: your teacher decides where you work."),
}

local function set_mode(new_mode)
	if new_mode == mode then
		return
	end
	mode = new_mode
	core.log("action", "[lep_desk] the class mode is " .. mode)
	for _, student in ipairs(lep_desk.get_students()) do
		core.chat_send_player(student, ANNOUNCEMENTS[mode])
	end
	clear_wilderness()
	lep_desk.refresh()
end

local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer >= SWEEP_INTERVAL then
		timer = 0
		clear_wilderness()
	end
end)

-- A mode never outlasts the teacher: the wilderness would stay closed
-- until one comes back.
lep_desk.register_on_unattended(function()
	set_mode(modes.LEISURE)
end)

local GROUP = S("Class mode")

local BUTTONS = {
	{ id = modes.LEISURE, title = S("Leisure"), done = S("Leisure: everything is open.") },
	{ id = modes.SELF_STUDY, title = S("Self-study"),
		done = S("Self-study: the wilderness is closed.") },
	{ id = modes.LESSON, title = S("Lesson"),
		done = S("Lesson: students go only where you send them.") },
}

for _, entry in ipairs(BUTTONS) do
	lep_desk.register_action("lep_desk:mode_" .. entry.id, {
		title = entry.title,
		privilege = lep_desk.PRIV_MODE,
		needs_targets = false,
		group = GROUP,
		is_active = function()
			return mode == entry.id
		end,
		run = function()
			set_mode(entry.id)
			return entry.done
		end,
	})
end
