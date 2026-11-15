-- Debug helpers. Only loaded when the setting "lep_debug" is true.

core.register_chatcommand("lep_lobby", {
	params = "[leave | rebuild]",
	description = "Go to the lobby, leave it for the wilderness, or rebuild the hall",
	privs = { lep_debug = true },
	func = function(name, param)
		local action = param:match("^%s*(%S*)")
		if action == "" then
			lep_lobby.enter(name, function(ok, err)
				if not ok then
					core.chat_send_player(name, "Enter failed: " .. tostring(err))
				end
			end)
			return true
		elseif action == "leave" then
			return lep_places.move(name, lep_places.WILDERNESS)
		elseif action == "rebuild" then
			lep_lobby.rebuild(function()
				core.chat_send_player(name, "Hall rebuilt")
			end)
			return true, "Rebuilding the hall ..."
		end
		return false, "Usage: /lep_lobby [leave | rebuild]"
	end,
})
