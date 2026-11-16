-- Chat command of lep_bridge, for people who look after the server.

core.register_chatcommand("lep_bridge", {
	description = "Show whether the world is connected to the LEP backend",
	privs = { server = true },
	func = function()
		local status = lep_bridge.get_status()
		if not status.active then
			return true, "Not connected: " .. status.reason .. ".\n"
				.. status.queued .. " event(s) waiting."
		end
		local contact = status.last_contact
			and (os.time() - status.last_contact) .. " s ago" or "never"
		return true, "Backend: " .. status.url .. "\n"
			.. "Last answer: " .. contact .. (status.failing and " (failing right now)" or "") .. "\n"
			.. status.queued .. " event(s) waiting."
	end,
})
