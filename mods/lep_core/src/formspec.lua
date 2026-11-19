-- Helper layer for formspecs. Pure Lua, no engine calls.
--
-- Every LEP window is written by hand with this builder. It takes care of
-- the two things that are easy to get wrong: escaping text and joining
-- the parts of an element. And it gives all windows the same look:
--   * a title that stands out, with a line below it (Builder:title)
--   * the same padding (formspec.PADDING)
--   * a button "Close" in the bottom right corner (Builder:close)
--   * two colours for buttons that stand out (Builder:highlight)
--   * one way to write headings inside a window and large text

local formspec = {}

-- Version of the formspec language all LEP windows use.
formspec.VERSION = 6

-- Sizes in formspec units.
formspec.PADDING = 0.375
formspec.SLOT = 1
formspec.SLOT_GAP = 0.25
-- Where the content of a window starts below its title, see Builder:title.
formspec.CONTENT_TOP = 1.45
formspec.BUTTON_HEIGHT = 0.8
-- Width of the button that closes a window.
formspec.CLOSE_WIDTH = 2

-- The two ways a button can stand out.
-- ACTIVE: the current position of a switch.
-- OTHER: something else than the window is mainly for, like going back.
formspec.ACTIVE = "active"
formspec.OTHER = "other"
local HIGHLIGHTS = { [formspec.ACTIVE] = "#30C030", [formspec.OTHER] = "#B05A2A" }

-- Colour of the lines that set parts of a window apart.
local LINE = "#FFFFFF80"
local LINE_HEIGHT = 0.03

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
		_width = width,
		_height = height,
		_parts = {
			"formspec_version[" .. formspec.VERSION .. "]",
			"size[" .. width .. "," .. height .. "]",
		},
	}, Builder)
end

--- Adds the title of the window: larger and bold, in the top left
-- corner, with a line below it across the window. Every window says
-- with it what it is about. What follows starts at formspec.CONTENT_TOP.
-- The text is escaped here.
function Builder:title(text)
	self:element("style_type", "label", "font=bold;font_size=*1.3")
	self:label(formspec.PADDING, 0.6, text)
	self:element("style_type", "label", "font=normal;font_size=*1")
	return self:separator(1.05)
end

--- Adds a heading inside a window: bold, in the size of the text. For
-- the parts of a large window. The text is escaped here.
function Builder:heading(x, y, text)
	self:element("style_type", "label", "font=bold")
	self:label(x, y, text)
	return self:element("style_type", "label", "font=normal")
end

--- Adds a line of large text, for the one thing a window is about, like
-- the task to solve. The text is escaped here.
function Builder:big_label(x, y, text)
	self:element("style_type", "label", "font_size=*1.6")
	self:label(x, y, text)
	return self:element("style_type", "label", "font_size=*1")
end

--- Makes a button stand out. Call it before the button is added.
-- @param kind formspec.ACTIVE or formspec.OTHER
function Builder:highlight(name, kind)
	local colour = assert(HIGHLIGHTS[kind], "highlight: unknown kind " .. tostring(kind))
	return self:element("style", formspec.escape(name), "bgcolor=" .. colour)
end

--- Adds the button that closes the window, in the bottom right corner.
-- Every window has one. It arrives as the field "close", together with
-- "quit". The label is escaped here.
function Builder:close(label)
	return self:button_exit(self._width - formspec.PADDING - formspec.CLOSE_WIDTH,
		self._height - formspec.PADDING - formspec.BUTTON_HEIGHT,
		formspec.CLOSE_WIDTH, formspec.BUTTON_HEIGHT, "close", label)
end

--- Adds a line across the window that sets apart what follows.
function Builder:separator(y)
	return self:element("box", { formspec.PADDING, y },
		{ self._width - 2 * formspec.PADDING, LINE_HEIGHT }, LINE)
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

--- Adds a table: rows of cells in columns. A click arrives as a field
-- named `name` that says which row and which column was hit, so a window
-- can tell a click on one cell from a click on the rest of the row.
-- @param columns List of column types as the engine knows them, for
--   example { "color", "text", "text,padding=1" }. A "color" column takes
--   no room: its cell holds the colour of the cells after it.
-- @param rows List of rows, each a list with one cell per column. The
--   cells are escaped here.
-- @param selected Optional index of the highlighted row.
function Builder:table(x, y, width, height, name, columns, rows, selected)
	assert(#columns > 0, "table: there must be at least one column")
	local cells = {}
	for row_index, row in ipairs(rows) do
		assert(#row == #columns, "table: row " .. row_index .. " must have "
			.. #columns .. " cells")
		for _, cell in ipairs(row) do
			cells[#cells + 1] = formspec.escape(cell)
		end
	end
	self:element("tablecolumns", unpack(columns))
	return self:element("table", { x, y }, { width, height }, formspec.escape(name),
		table.concat(cells, ","), selected or "")
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

--- Adds a one-line input field. The typed text arrives as a field named
-- `name`. Label and default text are escaped here.
function Builder:field(x, y, width, height, name, label, default)
	return self:element("field", { x, y }, { width, height }, formspec.escape(name),
		formspec.escape(label or ""), formspec.escape(default or ""))
end

--- Makes the Enter key in a field submit the window instead of closing
-- it, and puts the cursor into the field. The submit arrives with the
-- field `key_enter_field` set to `name`.
function Builder:submit_on_enter(name)
	self:element("field_close_on_enter", formspec.escape(name), "false")
	return self:element("set_focus", formspec.escape(name), "true")
end

--- Returns the finished formspec string.
function Builder:build()
	return table.concat(self._parts)
end

return formspec
