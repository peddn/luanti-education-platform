-- The portal of mental arithmetic in the learning hall.

local S = core.get_translator("lep_math")

lep_portals.register_learning_portal(lep_math.MODULE, {
	title = S("Mental arithmetic"),
	-- The colour of the display in the math room.
	colour = "#ff9020",
	place = lep_math.PLACE,
	enter = function(player_name)
		lep_rooms.enter(player_name, lep_math.ROOM_TYPE, function(ok, err)
			if not ok then
				core.chat_send_player(player_name,
					S("The math room is not available: @1", tostring(err)))
			end
		end)
	end,
})
