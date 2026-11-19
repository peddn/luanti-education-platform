-- The end of the year. The school administration closes the year in the
-- web application, and the backend orders every world to delete its
-- protocols. What students have reached stays: only what was written
-- down about them goes. See the concept, section 12.

local load = lep_core.loader("lep_bridge")
local orders = load("src/orders")
local reports = load("src/reports")

lep_bridge.register_job(reports.JOB_CLEAR_PROTOCOLS, function(payload)
	local order = orders.parse_clear(payload)
	if not order then
		return false, "the order cannot be read"
	end
	-- This is not written into a protocol: they are just being deleted.
	-- The backend keeps the note that the year was closed.
	core.log("action", "[lep_bridge] " .. order.by .. " closed the year: deleting all protocols")
	local deleted, failed = lep_core.protocols.clear_all()
	if failed > 0 then
		return false, failed .. " file(s) could not be deleted"
	end
	return true, "deleted " .. deleted .. " file(s)"
end)
