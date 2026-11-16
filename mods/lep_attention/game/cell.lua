-- The cell: one node wide, two nodes high, black and closed all around.
-- It is a room type of lep_rooms, so every student has their own, it is
-- protected, and the survival inventory is stored away while inside.

local S = core.get_translator("lep_attention")

local WALL = "lep_attention:wall"

lep_attention.ROOM_TYPE = "lep_attention:cell"

core.register_node(WALL, {
	description = "LEP attention cell wall",
	tiles = { "[fill:16x16:#000000" },
	sounds = default.node_sound_stone_defaults(),
	groups = { not_in_creative_inventory = 1 },
	diggable = false,
	is_ground_content = false,
	on_blast = function() end,
	can_dig = function() return false end,
})

-- lep_rooms builds a lit room with bright walls. The cell replaces all of
-- it: black walls, and plain air instead of the glowing air of the rooms.
local function furnish(_, geometry)
	local imin, imax = geometry.interior_min, geometry.interior_max
	for x = geometry.shell_min.x, geometry.shell_max.x do
		for y = geometry.shell_min.y, geometry.shell_max.y do
			for z = geometry.shell_min.z, geometry.shell_max.z do
				local inside = x >= imin.x and x <= imax.x and y >= imin.y and y <= imax.y
					and z >= imin.z and z <= imax.z
				core.set_node({ x = x, y = y, z = z }, { name = inside and "air" or WALL })
			end
		end
	end
end

-- Layer 2 belongs to this room type, see mods/README.md.
lep_rooms.register_type(lep_attention.ROOM_TYPE, {
	layer = 2,
	size = { x = 1, y = 2, z = 1 },
	-- Raise this when the cell changes, so existing cells are rebuilt.
	version = 1,
	privileges = {},
	title = S("Attention cell"),
	on_build = furnish,
})

lep_attention.PLACE = lep_rooms.get_place_id(lep_attention.ROOM_TYPE)
