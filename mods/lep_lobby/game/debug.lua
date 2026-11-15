-- Debug helpers. Only loaded when the setting "lep_debug" is true.

core.register_chatcommand("lep_lobby", {
	params = "[room [<player>] | leave | rebuild]",
	description = "Go to the lobby or a personal room, leave for the wilderness, "
		.. "or rebuild the lobby",
	privs = { lep_debug = true },
	func = function(name, param)
		local action, argument = param:match("^%s*(%S*)%s*(%S*)")
		if action == "" then
			lep_lobby.enter(name, function(ok, err)
				if not ok then
					core.chat_send_player(name, "Enter failed: " .. tostring(err))
				end
			end)
			return true
		elseif action == "room" then
			lep_lobby.enter_room(name, argument ~= "" and argument or nil, function(ok, err)
				if not ok then
					core.chat_send_player(name, "Room failed: " .. tostring(err))
				end
			end)
			return true
		elseif action == "leave" then
			return lep_places.move(name, lep_places.WILDERNESS)
		elseif action == "rebuild" then
			lep_lobby.rebuild(function()
				core.chat_send_player(name, "Lobby rebuilt")
			end)
			return true, "Rebuilding the lobby ..."
		end
		return false, "Usage: /lep_lobby [room [<player>] | leave | rebuild]"
	end,
})
