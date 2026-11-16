-- Chat command to reach the math room. A stopgap until the teacher's desk
-- and a portal in the lobby lead there.

local S = core.get_translator("lep_math")

core.register_chatcommand("lep_math", {
	params = "[leave]",
	description = S("Go to your math room, or leave it"),
	func = function(name, param)
		if not core.get_player_by_name(name) then
			return false, S("You have to be in the game.")
		end
		if param:match("^%s*leave%s*$") then
			if lep_places.get_place(name) ~= lep_math.PLACE then
				return false, S("You are not in your math room.")
			end
			-- A student who was sent by the teacher stays and is told why.
			return lep_rooms.leave(name) == true
		end
		local allowed, message = lep_places.may_go(name, lep_math.PLACE)
		if not allowed then
			return false, message
		end
		lep_rooms.enter(name, lep_math.ROOM_TYPE, function(ok, err)
			if not ok then
				core.chat_send_player(name, S("The math room is not available: @1", tostring(err)))
			end
		end)
		return true
	end,
})
