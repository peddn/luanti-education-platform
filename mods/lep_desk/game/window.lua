-- The window of the desk: students on the left, actions on the right.
--
-- What a teacher marked is kept here, on the server. The window only
-- says which line or button was pressed.

local load = lep_core.loader("lep_desk")
local desk = load("src/desk")
local S = core.get_translator("lep_desk")
local formspec = lep_core.formspec

local FORM = "lep_desk:desk"
local WIDTH, HEIGHT = 18, 11
local LIST_WIDTH = 12
-- Colours of the lines in the list.
local MARKED, UNMARKED = "#9CFF9C", "#BBBBBB"
-- Colour of the button that is the current position of a switch.
local ACTIVE = "#30C030"

-- Per teacher: selection (see src/desk.lua), status (last line of text),
-- open (true while the window is shown), students (the list the window
-- was drawn with, so a click hits the row the teacher saw), highlight
-- (name of the student whose row the teacher clicked last, or nil).
local desks = {}

local function state_of(teacher_name)
	if not desks[teacher_name] then
		desks[teacher_name] = { selection = desk.new_selection(), status = "" }
	end
	return desks[teacher_name]
end

-- The columns of the list. The first one only colours the row.
local COLUMNS = { "color", "text", "text,padding=1", "text,padding=2", "text,padding=2" }
-- The column with the box, as the engine counts it in a click.
local BOX_COLUMN = 2

local function box(marked)
	return marked and "[x]" or "[  ]"
end

-- The buttons under the list.
local HELPERS = {
	{ id = "all", title = S("Mark all") },
	{ id = "none", title = S("Mark none") },
	{ id = "invert", title = S("Invert") },
	{ id = "place", title = S("Same place") },
}

-- Students a teacher sent into a learning room are held there.
lep_desk.register_student_note(function(student)
	return lep_rooms.is_held(student) and S("sent") or nil
end)

-- Where a student is, for the overview, with the notes about them.
local function describe_place(student)
	local place = lep_places.get_place_title(lep_places.get_place(student) or "?")
	local notes = lep_desk.get_student_notes(student)
	if #notes > 0 then
		place = place .. " (" .. table.concat(notes, ", ") .. ")"
	end
	return place
end

-- "Mental arithmetic level 3" for every module.
local function describe_levels(student)
	local parts = {}
	for _, module_id in ipairs(lep_progress.get_module_ids()) do
		local info = lep_progress.get_progress(student, module_id)
		parts[#parts + 1] = S("@1 level @2", info.title, info.level)
	end
	return table.concat(parts, "   ")
end

local function show(teacher_name)
	local state = state_of(teacher_name)
	local students = lep_desk.get_students()
	state.students = students
	state.open = true

	local pad = formspec.PADDING
	local targets = desk.targets(state.selection, students)

	local rows = {}
	for _, student in ipairs(students) do
		local marked = desk.is_selected(state.selection, student)
		rows[#rows + 1] = { marked and MARKED or UNMARKED, box(marked), student,
			describe_place(student), describe_levels(student) }
	end

	local fs = formspec.new(WIDTH, HEIGHT)
		:label(pad, 0.55, S("Students (@1): click a box to mark", #students))
		:table(pad, 0.9, LIST_WIDTH, HEIGHT - 3.4, "students", COLUMNS, rows,
			desk.index_of(state.highlight, students))

	-- Helpers that set many boxes at once.
	local gap = 0.2
	local helper_width = (LIST_WIDTH - (#HELPERS - 1) * gap) / #HELPERS
	for index, helper in ipairs(HELPERS) do
		fs:button(pad + (index - 1) * (helper_width + gap), HEIGHT - 2.3, helper_width, 0.7,
			"mark_" .. helper.id, helper.title)
	end

	-- "All" also covers students who join later.
	fs:label(pad, HEIGHT - 1.05, state.selection.all and S("Marked: all (@1)", #targets)
		or S("Marked: @1 of @2", #targets, #students))
	fs:label(pad, HEIGHT - 0.5, state.status)

	local actions_x = pad + LIST_WIDTH + 0.4
	fs:label(actions_x, 0.55, S("Actions"))
	local actions = lep_desk.get_actions(teacher_name)
	for _, item in ipairs(desk.layout(actions, actions_x, 0.9, WIDTH - actions_x - pad)) do
		if item.kind == "heading" then
			fs:label(item.x, item.y, item.text)
		else
			local action = actions[item.index]
			local name = "action_" .. item.index
			if action.is_active and action.is_active() then
				-- The current position of a switch looks pressed.
				fs:element("style", name, "bgcolor=" .. ACTIVE)
			end
			fs:button(item.x, item.y, item.width, item.height, name, action.title)
		end
	end
	if #actions == 0 then
		fs:label(actions_x, 1.3, S("You may not use any actions."))
	end
	state.actions = actions

	core.show_formspec(teacher_name, FORM, fs:build())
end

--- Opens the desk for a teacher.
-- @return true, or false if the player may not open it or is not online
function lep_desk.open(teacher_name)
	if not core.get_player_by_name(teacher_name) or not lep_desk.may_open(teacher_name) then
		return false
	end
	show(teacher_name)
	return true
end

-- Open desks follow what happens: students come, go and change places.
local refresh_pending = false
local function refresh()
	if refresh_pending then
		return
	end
	refresh_pending = true
	core.after(0.3, function()
		refresh_pending = false
		for teacher_name, state in pairs(desks) do
			if state.open and lep_desk.may_open(teacher_name) then
				show(teacher_name)
			end
		end
	end)
end

--- Shows open desks again, for example after an action has finished.
lep_desk.refresh = refresh

lep_places.register_on_place_changed(refresh)
core.register_on_joinplayer(refresh)
core.register_on_leaveplayer(function(player)
	desks[player:get_player_name()] = nil
	refresh()
end)
lep_progress.register_on_level_changed(refresh)
lep_rooms.register_on_hold_changed(refresh)

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= FORM then
		return false
	end
	local teacher_name = player:get_player_name()
	local state = desks[teacher_name]
	if not state or not state.open then
		return true
	end
	if fields.quit then
		state.open = false
		return true
	end
	-- The privilege may have been taken away while the window was open.
	if not lep_desk.may_open(teacher_name) then
		state.open = false
		core.close_formspec(teacher_name, FORM)
		return true
	end

	if fields.students then
		local event = core.explode_table_event(fields.students)
		if event.type ~= "CHG" and event.type ~= "DCL" then
			return true
		end
		local target = (state.students or {})[event.row]
		if target == nil then
			return true
		end
		-- Every click highlights its row. The client has done that already;
		-- it is remembered for the next time the window is drawn.
		state.highlight = target
		if event.column ~= BOX_COLUMN then
			-- Only a click on the box changes who is marked.
			return true
		end
		state.selection = desk.toggle(state.selection, target, lep_desk.get_students())
		show(teacher_name)
		return true
	end

	local students = lep_desk.get_students()
	if fields.mark_all then
		state.selection = desk.new_selection()
		state.status = ""
	elseif fields.mark_none then
		state.selection = desk.select_none()
		state.status = ""
	elseif fields.mark_invert then
		state.selection = desk.invert(state.selection, students)
		state.status = ""
	elseif fields.mark_place then
		-- Everybody who is where the highlighted student is.
		local place = state.highlight and lep_places.get_place(state.highlight)
		if place then
			local names = {}
			for _, student in ipairs(students) do
				if lep_places.get_place(student) == place then
					names[#names + 1] = student
				end
			end
			state.selection = desk.select_names(names, students)
			state.status = S("Marked: everybody in @1", lep_places.get_place_title(place))
		else
			state.status = S("First click the row of a student.")
		end
	end
	if fields.mark_all or fields.mark_none or fields.mark_invert or fields.mark_place then
		show(teacher_name)
		return true
	end

	for index, action in ipairs(state.actions or {}) do
		if fields["action_" .. index] then
			local targets = action.needs_targets
				and desk.targets(state.selection, lep_desk.get_students()) or {}
			if action.needs_targets and #targets == 0 then
				state.status = S("Nobody is marked.")
			else
				local ok, text = lep_desk.run_action(teacher_name, action.id, targets)
				state.status = ok and (text or "") or S("That did not work.")
			end
			show(teacher_name)
			return true
		end
	end
	return true
end)
