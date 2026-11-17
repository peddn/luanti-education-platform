-- LEP Core: shared helpers for all Luanti Education Platform mods.

local modpath = core.get_modpath("lep_core")
local loader = dofile(modpath .. "/src/loader.lua")
local loaders = loader.new_set(core.get_modpath)
local load = loaders("lep_core")

lep_core = {}

--- Returns the load function of the given mod. Every file of a mod is
-- loaded only once, from wherever it is requested.
-- Usage in any file of another mod:
--   local load = lep_core.loader("lep_example")
--   local api = load("src/api")
function lep_core.loader(modname)
	return loaders(modname)
end

--- Event dispatcher factory, see src/events.lua.
lep_core.events = load("src/events")

--- Formspec builder, see src/formspec.lua. Every LEP window uses it.
lep_core.formspec = load("src/formspec")

--- Protocols: append-only files in the world folder, see
-- game/protocols.lua.
lep_core.protocols = load("game/protocols")

-- Text for signs the server sets up itself. Needs the mod signs_lib when
-- it is used.
lep_core.signs = load("game/signs")

core.log("action", "[lep_core] loaded")
