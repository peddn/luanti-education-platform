-- Pedestal and cups. The textures come from Minetest Game.

local load = lep_core.loader("lep_trophies")
local trophies = load("src/trophies")

local function unbreakable(def)
	def.groups = { not_in_creative_inventory = 1 }
	def.diggable = false
	def.is_ground_content = false
	def.drop = ""
	def.on_blast = function() end
	def.can_dig = function() return false end
	return def
end

lep_trophies.PEDESTAL = "lep_trophies:pedestal"

-- on_rightclick is added in game/pedestals.lua.
core.register_node(lep_trophies.PEDESTAL, unbreakable({
	description = "LEP trophy pedestal",
	tiles = { "default_stone_block.png" },
	sounds = default.node_sound_stone_defaults(),
}))

-- A cup: foot, stem, bowl and two handles.
local CUP = {
	type = "fixed",
	fixed = {
		{ -0.25, -0.5, -0.25, 0.25, -0.375, 0.25 },
		{ -0.0625, -0.375, -0.0625, 0.0625, -0.0625, 0.0625 },
		{ -0.25, -0.0625, -0.25, 0.25, 0.3125, 0.25 },
		{ -0.375, 0.0625, -0.0625, -0.25, 0.25, 0.0625 },
		{ 0.25, 0.0625, -0.0625, 0.375, 0.25, 0.0625 },
	},
}

local TEXTURES = {
	[trophies.BRONZE] = "default_bronze_block.png",
	[trophies.SILVER] = "default_steel_block.png",
	[trophies.GOLD] = "default_gold_block.png",
}

lep_trophies.CUPS = {}

for material, texture in pairs(TEXTURES) do
	local name = "lep_trophies:cup_" .. material
	core.register_node(name, unbreakable({
		description = "LEP trophy cup (" .. material .. ")",
		drawtype = "nodebox",
		node_box = CUP,
		selection_box = { type = "fixed", fixed = { -0.375, -0.5, -0.25, 0.375, 0.3125, 0.25 } },
		tiles = { texture },
		paramtype = "light",
		paramtype2 = "facedir",
		sunlight_propagates = true,
		sounds = default.node_sound_metal_defaults(),
	}))
	lep_trophies.CUPS[material] = name
end
