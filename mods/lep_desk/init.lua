-- LEP Desk: the teacher's desk. A window with the students, where they
-- are, and the actions a teacher may use on them.

local load = lep_core.loader(core.get_current_modname())

lep_desk = {}

load("game/api")
load("game/window")
load("game/actions")
load("game/modes")
load("game/daytime")
load("game/watch")
load("game/web_access")
load("game/commands")

core.log("action", "[lep_desk] loaded")
