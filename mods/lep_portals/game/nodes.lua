-- Nodes of the portals. The frame texture comes from Minetest Game, the
-- field textures belong to this mod.

local function unbreakable(def)
	def.groups = { not_in_creative_inventory = 1 }
	def.diggable = false
	def.is_ground_content = false
	def.drop = ""
	def.on_blast = function() end
	def.can_dig = function() return false end
	return def
end

-- Frame of the portals this mod builds itself. Players build theirs from
-- real obsidian.
core.register_node("lep_portals:frame", unbreakable({
	description = "LEP portal frame",
	tiles = { "default_obsidian.png" },
	sounds = default.node_sound_stone_defaults(),
}))

-- Platform around the fixed portal in the wilderness.
core.register_node("lep_portals:platform", unbreakable({
	description = "LEP portal platform",
	tiles = { "default_obsidian_brick.png" },
	sounds = default.node_sound_stone_defaults(),
}))

-- The field is a thin upright sheet. Players walk into it. With param2 0
-- it spans the x axis, with param2 1 the z axis.
local function field(def)
	def = unbreakable(def)
	def.drawtype = "nodebox"
	def.node_box = { type = "fixed", fixed = { -0.5, -0.5, -0.1, 0.5, 0.5, 0.1 } }
	def.paramtype = "light"
	def.paramtype2 = "facedir"
	def.use_texture_alpha = "blend"
	def.sunlight_propagates = true
	def.walkable = false
	def.pointable = false
	def.buildable_to = false
	def.floodable = false
	return def
end

core.register_node("lep_portals:field", field({
	description = "LEP portal field",
	tiles = { {
		name = "lep_portals_field.png",
		animation = { type = "vertical_frames", aspect_w = 16, aspect_h = 16, length = 1.6 },
	} },
	light_source = 11,
	post_effect_color = { a = 120, r = 120, g = 40, b = 200 },
}))

core.register_node("lep_portals:field_inactive", field({
	description = "LEP portal field (inactive)",
	tiles = { "lep_portals_field_inactive.png" },
}))
