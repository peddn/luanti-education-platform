-- Helper layer for formspecs. Pure Lua, no engine calls.
--
-- Every LEP window is written by hand with this builder. It takes care of
-- the two things that are easy to get wrong: escaping text and joining
-- the parts of an element.

local formspec = {}

-- Version of the formspec language all LEP windows use.
formspec.VERSION = 6

-- Sizes in formspec units.
formspec.PADDING = 0.375
formspec.SLOT = 1
formspec.SLOT_GAP = 0.25

local ESCAPES = { ["\\"] = "\\\\", ["["] = "\\[", ["]"] = "\\]", [";"] = "\\;", [","] = "\\," }

--- Returns text that is safe inside a formspec element.
function formspec.escape(text)
	return (tostring(text):gsub("[\\%[%];,]", ESCAPES))
end

--- Returns width or height of a row of inventory slots.
function formspec.slots(count)
	return count * formspec.SLOT + (count - 1) * formspec.SLOT_GAP
end

local Builder = {}
Builder.__index = Builder

--- Starts a window of the given size.
function formspec.new(width, height)
	assert(type(width) == "number" and type(height) == "number",
		"formspec.new: width and height must be numbers")
	return setmetatable({
		_parts = {
			"formspec_version[" .. formspec.VERSION .. "]",
			"size[" .. width .. "," .. height .. "]",
		},
	}, Builder)
end

--- Adds any element. Parts are joined with ";", a table part with ",".
-- Text has to be escaped by the caller, see the helpers below.
function Builder:element(name, ...)
	local parts = {}
	for index = 1, select("#", ...) do
		local part = select(index, ...)
		if type(part) == "table" then
			part = table.concat(part, ",")
		end
		parts[index] = tostring(part)
	end
	self._parts[#self._parts + 1] = name .. "[" .. table.concat(parts, ";") .. "]"
	return self
end

--- Adds a line of text. The text is escaped here.
function Builder:label(x, y, text)
	return self:element("label", { x, y }, formspec.escape(text))
end

--- Adds an inventory list with `columns` x `rows` slots.
function Builder:list(location, list_name, x, y, columns, rows)
	return self:element("list", formspec.escape(location), formspec.escape(list_name),
		{ x, y }, { columns, rows })
end

--- Lets shift-click move items between the lists added so far.
function Builder:listring(location, list_name)
	return self:element("listring", formspec.escape(location), formspec.escape(list_name))
end

--- Adds a list of text lines the player can select from. The lines are
-- escaped here. The selection arrives as a field named `name`.
-- @param selected Optional index of the selected line.
function Builder:textlist(x, y, width, height, name, lines, selected)
	local escaped = {}
	for index, line in ipairs(lines) do
		escaped[index] = formspec.escape(line)
	end
	return self:element("textlist", { x, y }, { width, height }, formspec.escape(name),
		table.concat(escaped, ","), selected or "")
end

--- Adds a button. The label is escaped here.
function Builder:button(x, y, width, height, name, label)
	return self:element("button", { x, y }, { width, height }, formspec.escape(name),
		formspec.escape(label))
end

--- Adds a button that also closes the window.
function Builder:button_exit(x, y, width, height, name, label)
	return self:element("button_exit", { x, y }, { width, height }, formspec.escape(name),
		formspec.escape(label))
end

--- Returns the finished formspec string.
function Builder:build()
	return table.concat(self._parts)
end

return formspec
