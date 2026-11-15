-- Nodes that make up a room. None of them can be dug or blown up.

-- The textures come from Minetest Game. They are referenced, not copied.
local function shell_node(name, description, texture)
	core.register_node(name, {
		description = description,
		tiles = { texture },
		groups = { not_in_creative_inventory = 1 },
		diggable = false,
		is_ground_content = false,
		on_blast = function() end,
		can_dig = function() return false end,
	})
end

shell_node("lep_rooms:floor", "LEP room floor", "default_junglewood.png")
shell_node("lep_rooms:wall", "LEP room wall", "default_silver_sandstone_block.png")
shell_node("lep_rooms:ceiling", "LEP room ceiling", "default_silver_sandstone_brick.png")

-- Invisible, glowing air. Rooms are filled with it, so every spot is evenly
-- lit, including the underside of things built in the middle of the room.
core.register_node("lep_rooms:air", {
	description = "LEP room air",
	drawtype = "airlike",
	paramtype = "light",
	sunlight_propagates = true,
	light_source = core.LIGHT_MAX,
	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = true,
	floodable = false,
	air_equivalent = true,
	drop = "",
	groups = { not_in_creative_inventory = 1 },
	on_blast = function() end,
})
