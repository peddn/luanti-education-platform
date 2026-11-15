-- LEP Lobby: the hall where players arrive, and the rules for first join
-- and death.

local load = lep_core.loader(core.get_current_modname())

lep_lobby = {}

load("game/nodes")
load("game/api")
load("game/rules")

if core.settings:get_bool("lep_debug", false) then
	load("game/debug")
end

core.log("action", "[lep_lobby] loaded")
