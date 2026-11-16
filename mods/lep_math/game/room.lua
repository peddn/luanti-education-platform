-- The math room: its room type, its furniture and what the display shows.

local load = lep_core.loader("lep_math")
local layout = load("src/layout")
local S = core.get_translator("lep_math")

lep_math.ROOM_TYPE = "lep_math:room"

local function set_if_different(pos, name)
	if core.get_node(pos).name ~= name then
		core.swap_node(pos, { name = name })
	end
end

local function furnish(_, geometry)
	local positions = layout.positions(geometry)
	for _, row in ipairs({ positions.task, positions.input }) do
		for _, pos in ipairs(row) do
			core.set_node(pos, { name = lep_math.display_node(" ") })
		end
	end
	for _, entry in ipairs(positions.keys) do
		-- Comma and minus are only put up when a task needs them.
		if entry.key ~= "comma" and entry.key ~= "minus" then
			core.set_node(entry.pos, { name = lep_math.key_node(entry.key) })
		end
	end
	core.set_node(positions.exit, { name = "lep_math:exit" })
end

-- Layer 1 belongs to this room type, see mods/README.md.
lep_rooms.register_type(lep_math.ROOM_TYPE, {
	layer = 1,
	size = layout.SIZE,
	-- Raise this when the furniture changes, so existing rooms are rebuilt.
	version = 2,
	privileges = {},
	title = S("Math room"),
	on_build = furnish,
})

lep_math.PLACE = lep_rooms.get_place_id(lep_math.ROOM_TYPE)

--- Shows a task and what the player typed on the display of their room.
-- @param text The task, for example "7+5".
-- @param input What stands behind the "=": the typed answer, or the
--   solution. Empty shows a question mark.
-- @param colour lep_math.NORMAL, RIGHT or WRONG, for the input row.
-- @param keys Table of extra keys the task needs: comma, minus.
function lep_math._show(player_name, text, input, colour, keys)
	local geometry = lep_rooms.get_geometry(player_name, lep_math.ROOM_TYPE)
	if not geometry then
		return
	end
	local positions = layout.positions(geometry)

	local task_row = layout.row(text, "left")
	local input_row = layout.row("=" .. (input ~= "" and input or "?"), "left")
	for column = 1, layout.COLUMNS do
		set_if_different(positions.task[column],
			lep_math.display_node(task_row[column], lep_math.NORMAL))
		set_if_different(positions.input[column],
			lep_math.display_node(input_row[column], colour))
	end

	for _, entry in ipairs(positions.keys) do
		if entry.key == "comma" or entry.key == "minus" then
			-- Without the key, the wall is whole again.
			set_if_different(entry.pos, keys and keys[entry.key]
				and lep_math.key_node(entry.key) or "lep_rooms:wall")
		end
	end
end
