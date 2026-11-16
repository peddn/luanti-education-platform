-- Connects the tab "Web access" of the desk to the backend: requests of
-- teachers go out as events, and the backend tells by job how a web
-- access stands. The desk knows nothing about the backend.

local load = lep_core.loader("lep_bridge")
local reports = load("src/reports")

if not core.global_exists("lep_desk") then
	return
end

local function send_holders(holders)
	lep_bridge.send(reports.EVENT_TEACHERS, reports.teachers(holders))
end

lep_desk.register_web_access_provider({
	is_available = lep_bridge.is_active,
	request = function(kind, account, email)
		lep_bridge.send(reports.EVENT_WEB_ACCESS, reports.web_access(account, kind, email))
	end,
})

-- The backend only listens to accounts this world named as teachers.
lep_desk.register_on_web_access_holders_changed(send_holders)

lep_bridge.register_job(reports.JOB_WEB_ACCESS_STATUS, function(payload)
	local account, address, pending = reports.parse_web_access_status(payload)
	if not account then
		return false, "the status cannot be read"
	end
	lep_desk.set_web_access(account, address, pending)
	return true, "noted"
end)

core.register_on_mods_loaded(function()
	if not lep_bridge.is_active() then
		return
	end
	-- The whole list at every start. The backend answers with how each
	-- web access stands, so the copy of this world is fresh.
	core.after(0, function()
		send_holders(lep_desk.get_web_access_holders())
	end)
end)
