-- LEP Chat: records what is written in the chat and on signs, and lets
-- teachers mute students.

local load = lep_core.loader(core.get_current_modname())

lep_chat = {}

load("game/record")
load("game/mute")
load("game/commands")

core.log("action", "[lep_chat] loaded")
