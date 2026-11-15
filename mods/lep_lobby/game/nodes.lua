-- Nodes of the lobby. None of them can be dug, caught or blown up.
-- Textures and sounds come from Minetest Game. They are referenced, not
-- copied.

local function unbreakable(def)
	def.groups = { not_in_creative_inventory = 1 }
	def.diggable = false
	def.is_ground_content = false
	def.drop = ""
	def.on_blast = function() end
	def.can_dig = function() return false end
	return def
end

core.register_node("lep_lobby:floor", unbreakable({
	description = "LEP lobby floor",
	tiles = { "default_obsidian_block.png" },
	sounds = default.node_sound_stone_defaults(),
}))

core.register_node("lep_lobby:glass", unbreakable({
	description = "LEP lobby glass",
	drawtype = "glasslike_framed_optional",
	tiles = { "default_glass.png", "default_glass_detail.png" },
	use_texture_alpha = "clip",
	paramtype = "light",
	sunlight_propagates = true,
	sounds = default.node_sound_glass_defaults(),
}))

core.register_node("lep_lobby:lamp", unbreakable({
	description = "LEP lobby lamp",
	drawtype = "glasslike",
	tiles = { "default_meselamp.png" },
	paramtype = "light",
	sunlight_propagates = true,
	light_source = core.LIGHT_MAX,
	sounds = default.node_sound_glass_defaults(),
}))

-- Name sign above the door of a personal room. The name is its infotext.
core.register_node("lep_lobby:room_sign", unbreakable({
	description = "LEP lobby room sign",
	drawtype = "nodebox",
	tiles = { "default_wood.png" },
	paramtype = "light",
	paramtype2 = "wallmounted",
	sunlight_propagates = true,
	walkable = false,
	node_box = {
		type = "wallmounted",
		wall_top = { -0.4375, 0.4375, -0.3125, 0.4375, 0.5, 0.3125 },
		wall_bottom = { -0.4375, -0.5, -0.3125, 0.4375, -0.4375, 0.3125 },
		wall_side = { -0.5, -0.3125, -0.4375, -0.4375, 0.3125, 0.4375 },
	},
	sounds = default.node_sound_wood_defaults(),
}))

-- Decoration in the air. Players walk and fly through it, cannot point at
-- it and cannot catch it. Unlike the animals of Minetest Game these never
-- hide.
local function flying(def)
	def = unbreakable(def)
	def.drawtype = "plantlike"
	def.waving = 1
	def.paramtype = "light"
	def.sunlight_propagates = true
	def.walkable = false
	def.pointable = false
	def.buildable_to = false
	def.floodable = false
	return def
end

local function animated(texture, length)
	return { {
		name = texture,
		animation = { type = "vertical_frames", aspect_w = 16, aspect_h = 16, length = length },
	} }
end

core.register_node("lep_lobby:firefly", flying({
	description = "LEP lobby firefly",
	tiles = animated("fireflies_firefly_animated.png", 1.5),
	light_source = 10,
}))

-- The order matches the colour numbers of src/hall.lua.
lep_lobby.BUTTERFLY_NODES = {}
for index, colour in ipairs({ "white", "red", "violet" }) do
	local name = "lep_lobby:butterfly_" .. colour
	core.register_node(name, flying({
		description = "LEP lobby butterfly (" .. colour .. ")",
		tiles = animated("butterflies_butterfly_" .. colour .. "_animated.png", 3),
	}))
	lep_lobby.BUTTERFLY_NODES[index] = name
end
