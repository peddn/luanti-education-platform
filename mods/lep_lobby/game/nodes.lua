-- Nodes of the lobby. None of them can be dug or blown up.
-- The textures come from Minetest Game. They are referenced, not copied.

local function unbreakable(def)
	def.groups = { not_in_creative_inventory = 1 }
	def.diggable = false
	def.is_ground_content = false
	def.on_blast = function() end
	def.can_dig = function() return false end
	return def
end

core.register_node("lep_lobby:floor", unbreakable({
	description = "LEP lobby floor",
	tiles = { "default_junglewood.png" },
}))

core.register_node("lep_lobby:glass", unbreakable({
	description = "LEP lobby glass",
	drawtype = "glasslike_framed_optional",
	tiles = { "default_glass.png", "default_glass_detail.png" },
	use_texture_alpha = "clip",
	paramtype = "light",
	sunlight_propagates = true,
}))

core.register_node("lep_lobby:lamp", unbreakable({
	description = "LEP lobby lamp",
	drawtype = "glasslike",
	tiles = { "default_meselamp.png" },
	paramtype = "light",
	sunlight_propagates = true,
	light_source = core.LIGHT_MAX,
}))
