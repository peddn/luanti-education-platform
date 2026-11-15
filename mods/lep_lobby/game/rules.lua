-- Rules of the lobby: nobody builds, nobody takes damage, new players
-- arrive here and so do players who died without a bed.

local PLACE = lep_lobby.PLACE
local WELCOMED_KEY = "lep_lobby:welcomed"

-- Nobody may change the lobby.
local old_is_protected = core.is_protected

function core.is_protected(pos, name)
	if lep_lobby.is_inside(pos) then
		return true
	end
	return old_is_protected(pos, name)
end

-- Nobody takes damage in the lobby, from anything or anyone.
core.register_on_player_hpchange(function(player, hp_change)
	if hp_change < 0 and lep_places.get_place(player:get_player_name()) == PLACE then
		return 0
	end
	return hp_change
end, true)

-- First join: arrive in the lobby. Later joins keep the logout position.
core.register_on_joinplayer(function(player)
	local meta = player:get_meta()
	if meta:get_int(WELCOMED_KEY) == 1 then
		return
	end
	local name = player:get_player_name()
	lep_lobby.enter(name, function(ok, err)
		if ok then
			local joined = core.get_player_by_name(name)
			if joined then
				joined:get_meta():set_int(WELCOMED_KEY, 1)
			end
		else
			core.log("warning", "[lep_lobby] could not bring new player " .. name
				.. " to the lobby: " .. tostring(err))
		end
	end)
end)

local function has_bed(name)
	return rawget(_G, "beds") ~= nil
		and type(beds.spawn) == "table"
		and beds.spawn[name] ~= nil
end

-- Death: respawn in the lobby, unless the player has a bed. Then the beds
-- mod of Minetest Game places the player.
core.register_on_respawnplayer(function(player)
	local name = player:get_player_name()
	if has_bed(name) then
		return false
	end
	lep_lobby.enter(name)
	return true
end)
