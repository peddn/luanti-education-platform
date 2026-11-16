-- The tabs of the desk. Pure Lua, no engine calls.
--
-- The first tab is the desk itself: students and actions. Further tabs
-- are building blocks that any mod can register.

local tabs = {}

local Tabs = {}
Tabs.__index = Tabs

--- Creates an empty registry of tabs.
function tabs.new()
	return setmetatable({ _ids = {}, _defs = {} }, Tabs)
end

--- Registers a tab.
-- @param id Unique id, for example "lep_desk:web_access".
-- @param def Table with:
--   title      text on the tab
--   privilege  privilege a teacher needs to see and use the tab
--   build      function(fs, teacher_name, area) that adds the content to
--              the window. `area` is a table with x, y, width and height.
--   on_fields  function(teacher_name, fields) called when the teacher
--              pressed something on the tab. The window is drawn again
--              afterwards.
function Tabs:register(id, def)
	assert(type(id) == "string" and id ~= "", "tab id must be a non-empty string")
	assert(type(def) == "table", "tab definition must be a table")
	assert(not self._defs[id], "tab '" .. id .. "' already exists")
	assert(type(def.title) == "string" and def.title ~= "",
		"tab title must be a non-empty string")
	assert(type(def.privilege) == "string" and def.privilege ~= "",
		"tab privilege must be a non-empty string")
	assert(type(def.build) == "function", "tab build must be a function")
	assert(type(def.on_fields) == "function", "tab on_fields must be a function")
	self._ids[#self._ids + 1] = id
	self._defs[id] = {
		id = id,
		title = def.title,
		privilege = def.privilege,
		build = def.build,
		on_fields = def.on_fields,
	}
end

--- Returns the tabs a teacher may use, in the order they were
-- registered.
-- @param has_privilege Function(privilege) returning true or false.
function Tabs:allowed(has_privilege)
	local list = {}
	for _, id in ipairs(self._ids) do
		local def = self._defs[id]
		if has_privilege(def.privilege) then
			list[#list + 1] = def
		end
	end
	return list
end

--- Returns the position of the tab with an id in a list from
-- Tabs:allowed, or nil.
function tabs.index_of(list, id)
	for index, def in ipairs(list) do
		if def.id == id then
			return index
		end
	end
	return nil
end

return tabs
