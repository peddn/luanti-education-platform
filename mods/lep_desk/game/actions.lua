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
			-- This also ends the hold of a student who was sent.
			if lep_rooms.get_current_room(student) and lep_rooms.leave(student, true) then
				count = count + 1
				core.chat_send_player(student,
					S("Your teacher has brought you back from the learning room."))
			end
		end
		return S("Brought back: @1 of @2", count, #targets)
	end,
})

-- Students who were sent into a learning room are held there. Releasing
-- lets them stay or leave as they like.
lep_desk.register_action("lep_desk:release", {
	title = S("Release: may leave the room"),
	privilege = lep_desk.PRIV_SEND,
	run = function(_, targets)
		local count = 0
		for _, student in ipairs(targets) do
			if lep_rooms.release(student) then
				count = count + 1
				core.chat_send_player(student, S("You may leave the learning room now."))
			end
		end
		return S("Released: @1 of @2", count, #targets)
	end,
})

-- Without a teacher nobody is held: a teacher who lost the connection
-- must not leave a class locked in. Sending them again is one click.
local function has_teacher(except)
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		if name ~= except and core.check_player_privs(name, { [lep_desk.PRIV_SEND] = true }) then
			return true
		end
	end
	return false
end

core.register_on_leaveplayer(function(player)
	if has_teacher(player:get_player_name()) then
		return
	end
	for _, student in ipairs(lep_rooms.release_all()) do
		core.log("action", "[lep_desk] released " .. student .. ": no teacher is online")
		if core.get_player_by_name(student) then
			core.chat_send_player(student, S("No teacher is online any more. "
				.. "You may leave the learning room now."))
		end
	end
end)
