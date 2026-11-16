-- LEP Quest Chest: task chests in the wilderness. A chest asks a short
-- task of a learning module instead of holding items.

local load = lep_core.loader(core.get_current_modname())

lep_quest_chest = {}

load("game/chests")
load("game/window")
load("game/spawn")
load("game/commands")

if core.settings:get_bool("lep_debug", false) then
	load("game/debug")
end

core.log("action", "[lep_quest_chest] loaded")
