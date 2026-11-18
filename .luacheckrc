std = "lua51"
max_line_length = 100

-- The engine API is only allowed in the game layer and in init.lua.
read_globals = {
	core = {
		other_fields = true,
		fields = {
			-- Mods may wrap the protection check.
			is_protected = { read_only = false },
		},
	},
	"vector",
	"VoxelArea",
	"ItemStack",
	-- Global of the beds mod from Minetest Game.
	"beds",
	-- Sound helpers of the default mod from Minetest Game.
	"default",
	-- Door mechanics of Minetest Game.
	"doors",
	-- Inventory window of Minetest Game.
	"sfinv",
	-- Third-party mod for readable signs, see third_party/mods.toml.
	"signs_lib",
	-- Third-party mod for achievements in survival.
	awards = {
		other_fields = true,
		fields = {
			-- Single achievements are switched off through their definition.
			registered_awards = { other_fields = true, read_only = false },
		},
	},
}

-- Globals defined by LEP mods.
globals = { "lep_core", "lep_places", "lep_rooms", "lep_lobby", "lep_progress", "lep_rewards", "lep_trophies", "lep_math", "lep_quest_chest", "lep_desk", "lep_chat", "lep_attention", "lep_portals", "lep_bridge", "lep_accounts" }

exclude_files = { ".dev/", "third_party/", "**/spec/fixtures/" }

-- The pure cores must not touch the engine.
files["mods/*/src/"] = {
	new_read_globals = {},
	new_globals = {},
}

files["mods/*/spec/"] = {
	std = "+busted",
}
