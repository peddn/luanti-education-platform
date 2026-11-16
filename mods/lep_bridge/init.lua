-- LEP Bridge: connects the world to the backend. The world always calls;
-- the backend never reaches into the world.

local load = lep_core.loader(core.get_current_modname())

lep_bridge = {}

-- The engine hands out network access only here, while the mod loads,
-- and only to mods listed in the setting secure.http_mods.
local http = core.request_http_api()

load("game/sync").start(http)
load("game/reports")
load("game/web_access")
load("game/commands")

core.log("action", "[lep_bridge] loaded")
