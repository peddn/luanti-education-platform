-- LEP Attention: the attention mode. Students wait in a dark cell until
-- the teacher lets them go on.

local load = lep_core.loader(core.get_current_modname())

lep_attention = {}

load("game/cell")
load("game/effects")
load("game/api")
load("game/desk")

core.log("action", "[lep_attention] loaded")
