-- LEP Portals: the fixed pair between lobby and wilderness and the
-- personal pair between a player's room and their plot.

local load = lep_core.loader(core.get_current_modname())

lep_portals = {}

load("game/nodes")
load("game/portals")

core.log("action", "[lep_portals] loaded")
