-- Loads Lua files of a mod relative to its directory and caches the result.
-- Pure Lua: the base path is passed in, so this works without the engine.

local loader = {}

--- Creates a load function for one mod directory.
-- @param base_path Directory of the mod, without trailing slash.
-- @return function(name) Loads "<base_path>/<name>.lua" once and returns
--         whatever the file returns.
function loader.new(base_path)
	assert(type(base_path) == "string" and base_path ~= "",
		"loader.new: base_path must be a non-empty string")

	local cache = {}

	return function(name)
		assert(type(name) == "string" and name ~= "",
			"load: name must be a non-empty string")
		assert(not name:find("..", 1, true),
			"load: name must not contain '..'")

		local cached = cache[name]
		if cached ~= nil then
			return cached.value
		end

		local chunk, err = loadfile(base_path .. "/" .. name .. ".lua")
		if not chunk then
			error("load: cannot load '" .. name .. "': " .. tostring(err), 2)
		end

		local value = chunk()
		cache[name] = { value = value }
		return value
	end
end

return loader
