-- LEP Math: mental arithmetic in the player's learning room.

local load = lep_core.loader(core.get_current_modname())

lep_math = {}

load("game/nodes")
load("game/module")
load("game/short_tasks")
load("game/room")
load("game/play")
load("game/commands")

if core.get_modpath("lep_portals") then
	load("game/portal")
end

if core.get_modpath("lep_desk") then
	load("game/desk")
end

core.log("action", "[lep_math] loaded")
