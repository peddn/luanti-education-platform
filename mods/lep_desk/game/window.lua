-- The window of the desk: students on the left, actions on the right.
--
-- What a teacher marked is kept here, on the server. The window only
-- says which line or button was pressed.

local load = lep_core.loader("lep_desk")
local desk = load("src/desk")
local S = core.get_translator("lep_desk")
local formspec = lep_core.formspec

local FORM = "lep_desk:desk"
local WIDTH, HEIGHT = 18, 10
local LIST_WIDTH = 12
-- Colours of the lines in the list.
local MARKED, UNMARKED = "#9CFF9C", "#BBBBBB"

-- Per teacher: selection (see src/desk.lua), status (last line of text),
-- open (true while the window is shown), students (the list the window
-- was drawn with, so a click hits the row the teacher saw), highlight
-- (the row the teacher clicked last: desk.ALL, a name or nil).
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

-- Where a student is, for the overview.
local function describe_place(student)
	local place = lep_places.get_place_title(lep_places.get_place(student) or "?")
	if lep_rooms.is_held(student) then
		place = S("@1 (sent)", place)
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

	local all = state.selection.all
	local rows = { { all and MARKED or UNMARKED, box(all),
		S("All students (@1)", #students), "", "" } }
	for _, student in ipairs(students) do
		local marked = desk.is_selected(state.selection, student)
		rows[#rows + 1] = { marked and MARKED or UNMARKED, box(marked), student,
			describe_place(student), describe_levels(student) }
	end

	local fs = formspec.new(WIDTH, HEIGHT)
		:label(pad, 0.55, S("Students: click a box to mark"))
		:table(pad, 0.9, LIST_WIDTH, HEIGHT - 2.4, "students", COLUMNS, rows,
			desk.target_row(state.highlight, students))
		:label(pad, HEIGHT - 1.05, S("Marked: @1", #targets))
		:label(pad, HEIGHT - 0.5, state.status)

	local actions_x = pad + LIST_WIDTH + 0.4
	fs:label(actions_x, 0.55, S("Actions"))
	local actions = lep_desk.get_actions(teacher_name)
	for index, action in ipairs(actions) do
		fs:button(actions_x, 0.9 + (index - 1) * 1, WIDTH - actions_x - pad, 0.8,
			"action_" .. index, action.title)
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
		local target = desk.row_target(event.row, state.students or {})
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
		if target == desk.ALL then
			state.selection = desk.toggle_all(state.selection)
		else
			state.selection = desk.toggle(state.selection, target, lep_desk.get_students())
		end
		show(teacher_name)
		return true
	end

	for index, action in ipairs(state.actions or {}) do
		if fields["action_" .. index] then
			local targets = desk.targets(state.selection, lep_desk.get_students())
			if #targets == 0 then
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
