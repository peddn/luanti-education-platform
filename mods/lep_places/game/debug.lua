-- Debug helpers. Only loaded when the setting "lep_debug" is true.
-- Provides a test place and a chat command to move between places.

local TEST_PLACE = "lep_places:debug_room"
local TEST_POS = { x = 0, y = 20000, z = 0 }
local FLOOR_RADIUS = 4

core.register_privilege("lep_debug", {
	description = "Can use LEP debug commands",
	give_to_singleplayer = true,
	give_to_admin = true,
})

core.register_node("lep_places:debug_floor", {
	description = "LEP debug floor",
	tiles = { "[fill:16x16:#7a8b99" },
	groups = { not_in_creative_inventory = 1 },
	diggable = false,
	on_blast = function() end,
})

lep_places.register_place(TEST_PLACE, {
	inventory = lep_places.INVENTORY_LEARNING,
	privileges = { fly = true },
	default_pos = { x = TEST_POS.x, y = TEST_POS.y + 1, z = TEST_POS.z },
})

-- Builds a small floor so the player does not fall after the teleport.
local function build_floor(callback)
	local min = { x = TEST_POS.x - FLOOR_RADIUS, y = TEST_POS.y, z = TEST_POS.z - FLOOR_RADIUS }
	local max = { x = TEST_POS.x + FLOOR_RADIUS, y = TEST_POS.y, z = TEST_POS.z + FLOOR_RADIUS }
	core.emerge_area(min, max, function(_, _, remaining)
		if remaining > 0 then
			return
		end
		for x = min.x, max.x do
			for z = min.z, max.z do
				core.set_node({ x = x, y = TEST_POS.y, z = z },
					{ name = "lep_places:debug_floor" })
			end
		end
		callback()
	end)
end

core.register_chatcommand("lep_place", {
	params = "[<place id>]",
	description = "Show the current place or move to a place. "
		.. "Ids: " .. lep_places.WILDERNESS .. ", " .. TEST_PLACE,
	privs = { lep_debug = true },
	func = function(name, param)
		local target = param:match("^%s*(%S+)%s*$")
		if not target then
			return true, "Current place: " .. tostring(lep_places.get_place(name))
		end
		if not lep_places.is_registered(target) then
			return false, "Unknown place: " .. target
		end

		local function move()
			local ok, err = lep_places.move(name, target)
			if not ok then
				core.chat_send_player(name, "Move failed: " .. tostring(err))
			else
				core.chat_send_player(name, "Moved to " .. target)
			end
		end

		if target == TEST_PLACE then
			build_floor(move)
		else
			move()
		end
		return true
	end,
})

lep_places.register_on_place_changed(function(name, old_place, new_place)
	core.chat_send_player(name, "[debug] place changed: " .. old_place
		.. " -> " .. new_place)
end)
