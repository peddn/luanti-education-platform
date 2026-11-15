-- Debug helpers. Only loaded when the setting "lep_debug" is true.
-- Provides a test room type and the /lep_room command.

local TEST_TYPE = "lep_rooms:debug"

core.register_node("lep_rooms:debug_block", {
	description = "LEP debug block",
	tiles = { "[fill:16x16:#c0563f" },
	groups = { dig_immediate = 3, not_in_creative_inventory = 1 },
	drop = "",
})

lep_rooms.register_type(TEST_TYPE, {
	layer = 38,
	size = { x = 15, y = 9, z = 15 },
	version = 1,
	privileges = { fly = true },
	on_build = function(_, geometry)
		-- A small pillar in the middle shows that furnishing works.
		local x = geometry.spawn.x
		local z = math.floor((geometry.interior_min.z + geometry.interior_max.z) / 2)
		for y = geometry.interior_min.y, geometry.interior_min.y + 2 do
			core.set_node({ x = x, y = y, z = z }, { name = "lep_rooms:debug_block" })
		end
	end,
})

-- Hand out blocks in the test room, so building can be tried.
lep_places.register_on_place_changed(function(name, _, new_place)
	if new_place == lep_rooms.get_place_id(TEST_TYPE) then
		local player = core.get_player_by_name(name)
		if player then
			player:get_inventory():set_stack("main", 1, "lep_rooms:debug_block 99")
		end
	end
end)

local function tell(name, text)
	core.chat_send_player(name, text)
end

local function report(name, action)
	return function(ok, err)
		if ok then
			tell(name, action .. ": done")
		else
			tell(name, action .. " failed: " .. tostring(err))
		end
	end
end

local HELP = table.concat({
	"/lep_room enter [<type>]             enter your room (default: " .. TEST_TYPE .. ")",
	"/lep_room leave                      back to where you came from",
	"/lep_room info                       show the room you are in",
	"/lep_room clear                      empty the room you are in",
	"/lep_room rebuild                    rebuild the room you are in",
	"/lep_room rebuild <player> <type>    rebuild one room",
	"/lep_room rebuild all [<type>]       rebuild all rooms",
}, "\n")

local function command_rebuild(name, args)
	if #args == 0 then
		local type_id, owner = lep_rooms.get_current_room(name)
		if not type_id then
			return false, "You are not in a room."
		end
		lep_rooms.rebuild(owner, type_id, report(name, "Rebuild"))
		return true, "Rebuilding the room of " .. owner .. " ..."
	end

	if args[1] == "all" then
		lep_rooms.rebuild_all(args[2], function(done, failed)
			tell(name, "Rebuild all: " .. done .. " rooms rebuilt, " .. failed .. " failed")
		end)
		return true, "Rebuilding rooms ..."
	end

	if #args == 2 then
		lep_rooms.rebuild(args[1], args[2], report(name, "Rebuild"))
		return true, "Rebuilding the room of " .. args[1] .. " ..."
	end
	return false, HELP
end

core.register_chatcommand("lep_room", {
	params = "enter [<type>] | leave | info | clear | rebuild [...]",
	description = "Debug command for learning rooms",
	privs = { lep_debug = true },
	func = function(name, param)
		local args = {}
		for word in param:gmatch("%S+") do
			args[#args + 1] = word
		end
		local action = table.remove(args, 1)

		if action == "enter" then
			lep_rooms.enter(name, args[1] or TEST_TYPE, report(name, "Enter"))
			return true
		elseif action == "leave" then
			return lep_rooms.leave(name)
		elseif action == "info" then
			local type_id, owner = lep_rooms.get_current_room(name)
			if not type_id then
				return true, "You are not in a room. Types: "
					.. table.concat(lep_rooms.get_types(), ", ")
			end
			return true, "Room type " .. type_id .. ", owner " .. owner
		elseif action == "clear" then
			local type_id, owner = lep_rooms.get_current_room(name)
			if not type_id then
				return false, "You are not in a room."
			end
			lep_rooms.clear_interior(owner, type_id, report(name, "Clear"))
			return true
		elseif action == "rebuild" then
			return command_rebuild(name, args)
		end
		return false, HELP
	end,
})
