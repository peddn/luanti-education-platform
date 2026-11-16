-- Public API of lep_desk: privileges and the registry of actions.

local load = lep_core.loader("lep_desk")
local desk = load("src/desk")

local actions = desk.new_actions()

-- Every action a teacher takes at the desk is written down.
local protocol = lep_core.protocols.open("desk", { "account", "action", "targets" })

lep_desk.PRIV_VIEW = "lep_view_players"
lep_desk.PRIV_SEND = "lep_send_players"
lep_desk.PRIV_TIME = "lep_set_time"

core.register_privilege(lep_desk.PRIV_VIEW, {
	description = "Can open the teacher's desk and see where the students are",
	give_to_singleplayer = false,
	give_to_admin = true,
})

core.register_privilege(lep_desk.PRIV_SEND, {
	description = "Can send students into learning rooms and bring them back",
	give_to_singleplayer = false,
	give_to_admin = true,
})

core.register_privilege(lep_desk.PRIV_TIME, {
	description = "Can set the time of day of the world at the teacher's desk",
	give_to_singleplayer = false,
	give_to_admin = true,
})

--- Returns true if a player may open the desk.
function lep_desk.may_open(player_name)
	return core.check_player_privs(player_name, { [lep_desk.PRIV_VIEW] = true })
end

--- Returns the names of the students who are online, sorted: all players
-- who may not open the desk themselves.
function lep_desk.get_students()
	local online = {}
	for _, player in ipairs(core.get_connected_players()) do
		online[#online + 1] = player:get_player_name()
	end
	return desk.students(online, lep_desk.may_open)
end

local dispatcher = lep_core.events.new(function(event_name, err)
	core.log("error", "[lep_desk] callback for " .. event_name .. " failed: "
		.. tostring(err))
end)

--- Registers a function() that is called when the last teacher leaves:
-- from then on nobody who may open the desk is online. Whatever teachers
-- imposed on students ends here, so a teacher who lost the connection or
-- forgot somebody leaves no student restricted.
lep_desk.register_on_unattended = dispatcher:registrar("unattended")

core.register_on_leaveplayer(function(player)
	local leaving = player:get_player_name()
	for _, other in ipairs(core.get_connected_players()) do
		local name = other:get_player_name()
		if name ~= leaving and lep_desk.may_open(name) then
			return
		end
	end
	dispatcher:emit("unattended")
end)

local note_providers = {}

--- Registers a function(student_name) that returns a short note about a
-- student for the overview of the desk, for example "muted", or nil.
function lep_desk.register_student_note(provider)
	assert(type(provider) == "function", "register_student_note: provider must be a function")
	note_providers[#note_providers + 1] = provider
end

--- Returns the notes about a student as a list of texts.
function lep_desk.get_student_notes(student_name)
	local notes = {}
	for _, provider in ipairs(note_providers) do
		local ok, note = pcall(provider, student_name)
		if not ok then
			core.log("error", "[lep_desk] student note failed: " .. tostring(note))
		elseif type(note) == "string" and note ~= "" then
			notes[#notes + 1] = note
		end
	end
	return notes
end

--- Registers an action, a button of the desk. Learning modules add their
-- own actions this way.
-- @param id Unique id, for example "lep_math:send".
-- @param def Table with:
--   title      text on the button, already translated
--   privilege  privilege a teacher needs to see and use the action
--   run        function(teacher_name, targets, text), where `targets` is
--              the list of the chosen students' names and `text` what the
--              teacher typed into the text field of the desk, for actions
--              that show the students a text. It returns a line of
--              text for the teacher, or nil. The desk has checked the
--              privilege and that the targets are students who are online.
--   needs_targets  optional, default true. False for an action on the
--              whole world: it runs without marked students.
--   group      optional heading, already translated. Actions of a group
--              stand together as smaller buttons side by side.
--   is_active  optional function() returning true while the action is
--              the current position of a switch.
function lep_desk.register_action(id, def)
	actions:register(id, def)
end

--- Returns the actions a teacher may use, each with id and title.
function lep_desk.get_actions(teacher_name)
	return actions:allowed(function(privilege)
		return core.check_player_privs(teacher_name, { [privilege] = true })
	end)
end

--- Runs an action for a teacher. Everything is checked here again: the
-- desk, the privilege of the action, and that the targets are students
-- who are online right now.
-- @param text Optional text of the teacher for the students.
-- @return true and a line of text (or nil), or false and an error message
function lep_desk.run_action(teacher_name, action_id, targets, text)
	local action = actions:get(action_id)
	if not action then
		return false, "unknown action '" .. tostring(action_id) .. "'"
	end
	if not lep_desk.may_open(teacher_name)
			or not core.check_player_privs(teacher_name, { [action.privilege] = true }) then
		return false, "missing privilege"
	end

	local is_student = {}
	for _, name in ipairs(lep_desk.get_students()) do
		is_student[name] = true
	end
	local checked = {}
	for _, name in ipairs(targets) do
		if is_student[name] then
			checked[#checked + 1] = name
		end
	end

	protocol:append({
		account = teacher_name,
		action = action_id,
		targets = table.concat(checked, ","),
	})
	core.log("action", "[lep_desk] " .. teacher_name .. " used " .. action_id .. " on "
		.. (#checked > 0 and table.concat(checked, ", ") or "nobody"))

	local ok, result = pcall(action.run, teacher_name, checked,
		type(text) == "string" and text or "")
	if not ok then
		core.log("error", "[lep_desk] action " .. action_id .. " failed: " .. tostring(result))
		return false, "the action failed"
	end
	return true, type(result) == "string" and result or nil
end

--- Returns the last entries of the desk protocol, oldest first, each with
-- time, account, action and targets.
function lep_desk.get_log(limit)
	return protocol:read(nil, limit)
end
