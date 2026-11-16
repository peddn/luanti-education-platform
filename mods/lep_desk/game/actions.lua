-- The actions the desk brings along itself.

local S = core.get_translator("lep_desk")

-- Brings students out of their learning rooms, back to where they were
-- before: lobby or wilderness. What they solved so far is kept, because
-- progress is saved with every task.
lep_desk.register_action("lep_desk:bring_back", {
	title = S("Bring back from learning rooms"),
	privilege = lep_desk.PRIV_SEND,
	run = function(_, targets)
		local count = 0
		for _, student in ipairs(targets) do
			if lep_rooms.get_current_room(student) and lep_rooms.leave(student) then
				count = count + 1
				core.chat_send_player(student,
					S("Your teacher has brought you back from the learning room."))
			end
		end
		return S("Brought back: @1 of @2", count, #targets)
	end,
})
