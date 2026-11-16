-- LEP Core: shared helpers for all Luanti Education Platform mods.

local modpath = core.get_modpath("lep_core")
local loader = dofile(modpath .. "/src/loader.lua")
local load = loader.new(modpath)

lep_core = {}

--- Returns a load function for the given mod.
-- Usage in another mod's init.lua:
--   local load = lep_core.loader(core.get_current_modname())
--   local api = load("src/api")
function lep_core.loader(modname)
	local path = core.get_modpath(modname)
	assert(path, "lep_core.loader: unknown mod '" .. tostring(modname) .. "'")
	return loader.new(path)
end

--- Event dispatcher factory, see src/events.lua.
lep_core.events = load("src/events")

--- Formspec builder, see src/formspec.lua. Every LEP window uses it.
lep_core.formspec = load("src/formspec")

--- Protocols: append-only files in the world folder, see
-- game/protocols.lua.
lep_core.protocols = load("game/protocols")

core.log("action", "[lep_core] loaded")
