std = "lua51"
max_line_length = 100

-- The engine API is only allowed in the game layer and in init.lua.
read_globals = { "core" }

-- Globals defined by LEP mods.
globals = { "lep_core" }

exclude_files = { ".dev/", "third_party/", "**/spec/fixtures/" }

-- The pure cores must not touch the engine.
files["mods/*/src/"] = {
	new_read_globals = {},
	new_globals = {},
}

files["mods/*/spec/"] = {
	std = "+busted",
}
