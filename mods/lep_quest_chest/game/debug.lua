-- Debug helpers. Only loaded when the setting "lep_debug" is true.

local load = lep_core.loader("lep_quest_chest")
local world = load("game/chests")

if not core.registered_privileges.lep_debug then
	core.register_privilege("lep_debug", {
		description = "Can use LEP debug commands",
		give_to_singleplayer = false,
	})
end

local function list()
	local now = os.time()
	local lines = {}
	for _, pos in ipairs(world.store:positions()) do
		local expires = world.store:expires_at(pos)
		lines[#lines + 1] = core.pos_to_string(pos) .. "  "
			.. (expires and ("disappears in " .. math.max(0, expires - now) .. " s")
				or "permanent")
	end
	if #lines == 0 then
		return "There are no task chests."
	end
	return #lines .. " task chests:\n" .. table.concat(lines, "\n")
end

core.register_chatcommand("lep_chests", {
	params = "[spawn | age <minutes>]",
	description = "List the task chests, let one appear near you, or make the spawned "
		.. "chests older, as if minutes had passed",
	privs = { lep_debug = true },
	func = function(name, param)
		local action, value = param:match("^%s*(%S*)%s*(%S*)")
		if action == "" then
			return true, list()
		elseif action == "spawn" then
			local player = core.get_player_by_name(name)
			if not player then
				return false, "You have to be in the game."
			end
			local pos = player:get_pos()
			local spot = lep_quest_chest.spawn_near(pos)
			if not spot then
				return false, "No suitable spot found. Try again or move to open land."
			end
			return true, "Chest at " .. core.pos_to_string(spot) .. ", "
				.. math.floor(vector.distance(pos, spot) + 0.5) .. " nodes to the "
				.. lep_quest_chest.describe_direction(pos, spot) .. "."
		elseif action == "age" and tonumber(value) then
			world.store:age(tonumber(value) * 60)
			world.save()
			return true, "The spawned chests are now " .. value .. " minutes older.\n" .. list()
		end
		return false, "Usage: /lep_chests [spawn | age <minutes>]"
	end,
})
