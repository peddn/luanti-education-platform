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
}

-- Globals defined by LEP mods.
globals = { "lep_core", "lep_places", "lep_rooms" }

exclude_files = { ".dev/", "third_party/", "**/spec/fixtures/" }

-- The pure cores must not touch the engine.
files["mods/*/src/"] = {
	new_read_globals = {},
	new_globals = {},
}

files["mods/*/spec/"] = {
	std = "+busted",
}
