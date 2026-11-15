-- Nodes that make up a room. None of them can be dug or blown up.

local function shell_node(name, description, color, light)
	core.register_node(name, {
		description = description,
		tiles = { "[fill:16x16:" .. color },
		light_source = light,
		groups = { not_in_creative_inventory = 1 },
		diggable = false,
		is_ground_content = false,
		on_blast = function() end,
		can_dig = function() return false end,
	})
end

shell_node("lep_rooms:floor", "LEP room floor", "#b9b4a8", 0)
shell_node("lep_rooms:wall", "LEP room wall", "#d9d6cc", 0)
shell_node("lep_rooms:ceiling", "LEP room ceiling", "#f2f0e8", core.LIGHT_MAX)

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
