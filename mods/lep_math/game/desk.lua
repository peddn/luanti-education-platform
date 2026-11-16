-- The button of mental arithmetic at the teacher's desk.

local S = core.get_translator("lep_math")

lep_desk.register_action("lep_math:send", {
	title = S("Send to the math room"),
	privilege = lep_desk.PRIV_SEND,
	run = function(teacher_name, targets)
		local sent = 0
		for _, student in ipairs(targets) do
			if lep_places.get_place(student) == lep_math.PLACE then
				-- Already there, by their own choice: from now on held.
				if lep_rooms.hold(student) then
					sent = sent + 1
					core.chat_send_player(student,
						S("Your teacher wants you to stay in the math room."))
				end
			else
				sent = sent + 1
				lep_rooms.enter(student, lep_math.ROOM_TYPE, function(ok, err)
					if ok then
						-- Sent students stay until they are brought back or
						-- released.
						lep_rooms.hold(student)
						core.chat_send_player(student,
							S("Your teacher has sent you to the math room."))
					else
						core.chat_send_player(teacher_name, S(
							"@1 could not be sent to the math room: @2", student, tostring(err)))
					end
				end)
			end
		end
		return S("Sent to the math room: @1 of @2", sent, #targets)
	end,
})
