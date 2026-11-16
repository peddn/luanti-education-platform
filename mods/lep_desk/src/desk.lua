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
--   run        function(teacher_name, targets) that does it. `targets` is
--              the list of the chosen students' names. It returns a line
--              of text for the teacher, or nil.
function Actions:register(id, def)
	assert(type(id) == "string" and id ~= "", "action id must be a non-empty string")
	assert(type(def) == "table", "action definition must be a table")
	assert(not self._defs[id], "action '" .. id .. "' already exists")
	assert(type(def.title) == "string" and def.title ~= "",
		"action title must be a non-empty string")
	assert(type(def.privilege) == "string" and def.privilege ~= "",
		"action privilege must be a non-empty string")
	assert(type(def.run) == "function", "action run must be a function")
	self._ids[#self._ids + 1] = id
	self._defs[id] = { id = id, title = def.title, privilege = def.privilege, run = def.run }
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

--------------------------------------------------------------------------
-- Rows of the list

-- The list shows one row for "all students" and one per student. A row is
-- named by what it stands for: desk.ALL or the name of a student.

desk.ALL = true

--- Returns what a row of the list stands for: desk.ALL for the first
-- row, the name of a student for the others, nil if there is no such row.
function desk.row_target(row, students)
	if row == 1 then
		return desk.ALL
	end
	return students[row - 1]
end

--- Returns the row that stands for a target, or nil if it is not in the
-- list, for example because the student left.
function desk.target_row(target, students)
	if target == desk.ALL then
		return 1
	end
	for index, student in ipairs(students) do
		if student == target then
			return index + 1
		end
	end
	return nil
end

return desk
