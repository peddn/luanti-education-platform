-- Where the things in the math room are. Pure Lua, no engine calls.
--
-- The player arrives at the back wall and looks at the front wall, which
-- carries the display: the task in the upper row, the input in the lower.
-- The keypad stands upright in the wall to the right.
--
-- Display, keypad and exit are set into the walls, flush with them. Their
-- positions are therefore one node outside the inner space of the room.

local layout = {}

-- Inner size of the room.
layout.SIZE = { x = 9, y = 5, z = 7 }
-- Width of the display in characters.
layout.COLUMNS = layout.SIZE.x

-- Keys from the top row down, left to right as the player sees them. The
-- fourth column is only there in levels that need it.
layout.KEYS = {
	{ "7", "8", "9" },
	{ "4", "5", "6" },
	{ "1", "2", "3", "comma" },
	{ "back", "0", "ok", "minus" },
}

--- Returns the positions of the room's furniture.
-- @param geometry As lep_rooms reports it: interior_min, interior_max, spawn.
-- @return Table with:
--   task   list of positions of the upper display row, left to right
--   input  list of positions of the lower display row, left to right
--   keys   list of { pos = ..., key = ... }
--   exit   position of the exit block
function layout.positions(geometry)
	local min, max = geometry.interior_min, geometry.interior_max
	local result = { task = {}, input = {}, keys = {} }

	-- Looking at the front wall (+z), left is -x.
	for column = 1, layout.COLUMNS do
		local x = min.x + column - 1
		result.task[column] = { x = x, y = min.y + 2, z = max.z + 1 }
		result.input[column] = { x = x, y = min.y + 1, z = max.z + 1 }
	end

	-- Looking at the right wall (+x), left is +z. The lowest row of keys is
	-- at floor level.
	for row, keys in ipairs(layout.KEYS) do
		for column, key in ipairs(keys) do
			result.keys[#result.keys + 1] = {
				key = key,
				pos = { x = max.x + 1, y = min.y + 4 - row, z = max.z - 1 - column },
			}
		end
	end

	-- In the left wall, beside the place where the player arrives.
	result.exit = { x = min.x - 1, y = min.y + 1, z = min.z + 1 }
	return result
end

--- Returns the characters for a display row, padded to its width.
-- @param align "left" or "right".
function layout.row(text, align)
	local characters = {}
	for character in text:gmatch(".") do
		characters[#characters + 1] = character
	end
	local padding = layout.COLUMNS - #characters
	local row = {}
	for column = 1, layout.COLUMNS do
		local index = align == "right" and column - padding or column
		row[column] = characters[index] or " "
	end
	return row
end

return layout
