-- Display, keys and exit of the math room. All textures belong to this
-- mod, see scripts/make-math-textures.py.

local S = core.get_translator("lep_math")

-- Characters of a task and the glyph texture for each.
local GLYPHS = {
	["+"] = "plus", ["-"] = "minus", ["*"] = "times", ["/"] = "divide",
	["="] = "equals", [","] = "comma", ["?"] = "question",
}
for digit = 0, 9 do
	GLYPHS[tostring(digit)] = tostring(digit)
end

-- The display glows in one of three colours.
lep_math.NORMAL = "normal"
lep_math.RIGHT = "right"
lep_math.WRONG = "wrong"

local COLOURS = {
	[lep_math.NORMAL] = "#ffb300",
	[lep_math.RIGHT] = "#48f070",
	[lep_math.WRONG] = "#ff5040",
}

local function unbreakable(def)
	def.groups = { not_in_creative_inventory = 1 }
	def.diggable = false
	def.is_ground_content = false
	def.drop = ""
	def.on_blast = function() end
	def.can_dig = function() return false end
	return def
end

local function sides(texture, plain)
	return { plain, plain, texture, texture, texture, texture }
end

local BLANK = "lep_math:display_blank"

core.register_node(BLANK, unbreakable({
	description = "LEP math display",
	tiles = { "lep_math_panel.png" },
	pointable = false,
	sounds = default.node_sound_glass_defaults(),
}))

for _, glyph in pairs(GLYPHS) do
	for colour, hex in pairs(COLOURS) do
		core.register_node("lep_math:display_" .. glyph .. "_" .. colour, unbreakable({
			description = "LEP math display (" .. glyph .. ")",
			tiles = sides("lep_math_panel.png^(lep_math_glyph_" .. glyph
				.. ".png^[multiply:" .. hex .. ")", "lep_math_panel.png"),
			paramtype = "light",
			light_source = 9,
			pointable = false,
			sounds = default.node_sound_glass_defaults(),
		}))
	end
end

--- Returns the display node for a character in a colour. Characters the
-- display cannot show give the blank node.
function lep_math.display_node(character, colour)
	local glyph = GLYPHS[character]
	if not glyph then
		return BLANK
	end
	return "lep_math:display_" .. glyph .. "_" .. (COLOURS[colour] and colour or lep_math.NORMAL)
end

-- Keys. What a click does is decided in game/play.lua.
local KEY_GLYPHS = { back = "back", ok = "ok", comma = "comma", minus = "minus" }
for digit = 0, 9 do
	KEY_GLYPHS[tostring(digit)] = tostring(digit)
end

local function clicked(key)
	return function(_, _, player)
		if player and player:is_player() then
			lep_math._on_key(player, key)
		end
	end
end

for key, glyph in pairs(KEY_GLYPHS) do
	core.register_node("lep_math:key_" .. key, unbreakable({
		description = "LEP math key (" .. key .. ")",
		tiles = sides("lep_math_key.png^(lep_math_glyph_" .. glyph
			.. ".png^[multiply:#1c2026)", "lep_math_key.png"),
		sounds = default.node_sound_stone_defaults(),
		on_punch = clicked(key),
		on_rightclick = clicked(key),
	}))
end

--- Returns the node of a key.
function lep_math.key_node(key)
	return "lep_math:key_" .. key
end

local function leave(_, _, player)
	if player and player:is_player() then
		lep_rooms.leave(player:get_player_name())
	end
end

core.register_node("lep_math:exit", unbreakable({
	description = "LEP math exit",
	tiles = sides("lep_math_key.png^(lep_math_glyph_exit.png^[multiply:#a02018)",
		"lep_math_key.png"),
	sounds = default.node_sound_stone_defaults(),
	on_punch = leave,
	on_rightclick = leave,
	on_construct = function(pos)
		core.get_meta(pos):set_string("infotext", S("Exit"))
	end,
}))
