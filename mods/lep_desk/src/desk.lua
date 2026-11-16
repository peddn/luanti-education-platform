-- The teacher's desk: its actions and the choice of targets. Pure Lua, no
-- engine calls.
--
-- The desk is a list of students and a list of actions. The teacher marks
-- students, or all of them, and presses an action. Actions are building
-- blocks that any mod can register.

local desk = {}

--------------------------------------------------------------------------
-- Actions

local Actions = {}
Actions.__index = Actions

--- Creates an empty registry of actions.
function desk.new_actions()
	return setmetatable({ _ids = {}, _defs = {} }, Actions)
end

--- Registers an action.
-- @param id Unique id, for example "lep_math:send".
-- @param def Table with:
--   title      text on the button
--   privilege  privilege a teacher needs to see and use the action
--   run        function(teacher_name, targets, text) that does it.
--              `targets` is the list of the chosen students' names, `text`
--              what the teacher typed into the text field of the desk. It
--              returns a line of text for the teacher, or nil.
--   needs_targets  optional, default true. False for an action on the
--              whole world, such as the time of day: it runs without
--              marked students and gets an empty list.
--   group      optional heading. Actions with the same group stand
--              together under it, as smaller buttons in two columns.
--   is_active  optional function() returning true while the action is
--              the current position of a switch. Its button is shown
--              as pressed.
function Actions:register(id, def)
	assert(type(id) == "string" and id ~= "", "action id must be a non-empty string")
	assert(type(def) == "table", "action definition must be a table")
	assert(not self._defs[id], "action '" .. id .. "' already exists")
	assert(type(def.title) == "string" and def.title ~= "",
		"action title must be a non-empty string")
	assert(type(def.privilege) == "string" and def.privilege ~= "",
		"action privilege must be a non-empty string")
	assert(type(def.run) == "function", "action run must be a function")
	assert(def.group == nil or (type(def.group) == "string" and def.group ~= ""),
		"action group must be a non-empty string")
	assert(def.is_active == nil or type(def.is_active) == "function",
		"action is_active must be a function")
	self._ids[#self._ids + 1] = id
	self._defs[id] = {
		id = id,
		title = def.title,
		privilege = def.privilege,
		run = def.run,
		needs_targets = def.needs_targets ~= false,
		group = def.group,
		is_active = def.is_active,
	}
end

--- Returns an action or nil.
function Actions:get(id)
	return self._defs[id]
end

--- Returns the actions a teacher may use, in the order they were
-- registered.
-- @param has_privilege Function(privilege) returning true or false.
function Actions:allowed(has_privilege)
	local list = {}
	for _, id in ipairs(self._ids) do
		local def = self._defs[id]
		if has_privilege(def.privilege) then
			list[#list + 1] = def
		end
	end
	return list
end

-- Sizes of the buttons, in formspec units.
desk.BUTTON_HEIGHT = 0.8
desk.BUTTON_PITCH = 1
desk.SMALL_HEIGHT = 0.7
desk.SMALL_PITCH = 0.85
desk.HEADING_HEIGHT = 0.75
desk.COLUMN_GAP = 0.2

--- Arranges the buttons of a list of actions in a column.
-- Actions without a group come first, one below the other. Every group
-- follows with its heading and its actions in two columns.
-- @param actions List of actions, as Actions:allowed returns it.
-- @param x, y Top left corner of the column.
-- @param width Width of the column.
-- @return List of items, each { kind = "button", index, x, y, width,
--   height } with the index of the action in `actions`, or
--   { kind = "heading", text, x, y }; and the y below the last item.
function desk.layout(actions, x, y, width)
	local items = {}
	local groups, by_group = {}, {}
	for index, action in ipairs(actions) do
		if not action.group then
			items[#items + 1] = { kind = "button", index = index, x = x, y = y,
				width = width, height = desk.BUTTON_HEIGHT }
			y = y + desk.BUTTON_PITCH
		else
			if not by_group[action.group] then
				by_group[action.group] = {}
				groups[#groups + 1] = action.group
			end
			table.insert(by_group[action.group], index)
		end
	end
	local small_width = (width - desk.COLUMN_GAP) / 2
	for _, group in ipairs(groups) do
		items[#items + 1] = { kind = "heading", text = group, x = x,
			y = y + desk.HEADING_HEIGHT / 2 }
		y = y + desk.HEADING_HEIGHT
		for position, index in ipairs(by_group[group]) do
			local column = (position - 1) % 2
			items[#items + 1] = { kind = "button", index = index,
				x = x + column * (small_width + desk.COLUMN_GAP), y = y,
				width = small_width, height = desk.SMALL_HEIGHT }
			if column == 1 or position == #by_group[group] then
				y = y + desk.SMALL_PITCH
			end
		end
	end
	return items, y
end

--------------------------------------------------------------------------
-- Students

--- Returns the students among the online players, sorted by name: all
-- who may not open the desk themselves.
-- @param online List of the names of the online players.
-- @param may_open Function(name) returning true for those with a desk.
function desk.students(online, may_open)
	local list = {}
	for _, name in ipairs(online) do
		if not may_open(name) then
			list[#list + 1] = name
		end
	end
	table.sort(list)
	return list
end

--------------------------------------------------------------------------
-- Selection

-- A selection is either "all students" or a set of names. "All" means
-- whoever is a student at the moment an action runs, so students who join
-- later are included.

--- Returns a new selection: all students.
function desk.new_selection()
	return { all = true, names = {} }
end

--- Returns true if a student is part of the selection.
function desk.is_selected(selection, name)
	return selection.all or selection.names[name] == true
end

--- Returns the selection after a click on the line "all students": it
-- switches between all and nobody.
function desk.toggle_all(selection)
	return { all = not selection.all, names = {} }
end

--- Returns the selection after a click on a student. From "all", a click
-- takes this one student out.
-- @param students The current list of students.
function desk.toggle(selection, name, students)
	local names = {}
	for _, student in ipairs(students) do
		if desk.is_selected(selection, student) then
			names[student] = true
		end
	end
	names[name] = not names[name] or nil

	-- Marking everybody one by one is the same as "all".
	local all = #students > 0
	for _, student in ipairs(students) do
		all = all and names[student] == true
	end
	if all then
		return { all = true, names = {} }
	end
	return { all = false, names = names }
end

--- Returns a selection of nobody.
function desk.select_none()
	return { all = false, names = {} }
end

--- Returns a selection of exactly these students.
-- @param names List of names. Names that are no students are left out.
-- @param students The current list of students.
function desk.select_names(names, students)
	local wanted = {}
	for _, name in ipairs(names) do
		wanted[name] = true
	end
	local selection = desk.select_none()
	for _, student in ipairs(students) do
		if wanted[student] then
			selection = desk.toggle(selection, student, students)
		end
	end
	return selection
end

--- Returns the opposite selection: whoever is marked is not, and the
-- other way round.
function desk.invert(selection, students)
	local names = {}
	for _, student in ipairs(students) do
		if not desk.is_selected(selection, student) then
			names[#names + 1] = student
		end
	end
	return desk.select_names(names, students)
end

--- Returns the names an action applies to: the selected students who are
-- still there, in the order of the list.
function desk.targets(selection, students)
	local list = {}
	for _, student in ipairs(students) do
		if desk.is_selected(selection, student) then
			list[#list + 1] = student
		end
	end
	return list
end

--- Returns the index of a student in the list, or nil if the student is
-- not in it, for example because they left.
function desk.index_of(name, students)
	for index, student in ipairs(students) do
		if student == name then
			return index
		end
	end
	return nil
end

return desk
