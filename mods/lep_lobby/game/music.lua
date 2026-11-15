-- Background music that only plays for players who are in the lobby.

local load = lep_core.loader("lep_lobby")
local music = load("src/music")

local SOUND = "lep_lobby_music"
-- Quiet enough to leave footsteps and other sounds audible.
local GAIN = 0.35
local FADE_SECONDS = 2

-- Sound handles by player name.
local handles = {}

local function update(player_name, place)
	local action = music.action(lep_lobby.PLACE, place, handles[player_name] ~= nil)
	if action == music.START then
		handles[player_name] = core.sound_play(
			{ name = SOUND, gain = GAIN, fade = GAIN / FADE_SECONDS },
			{ to_player = player_name, loop = true })
	elseif action == music.STOP then
		-- Fading to zero also stops the sound.
		core.sound_fade(handles[player_name], GAIN / FADE_SECONDS, 0)
		handles[player_name] = nil
	end
end

lep_places.register_on_place_changed(function(player_name, _, new_place)
	update(player_name, new_place)
end)

-- Players who logged out in the lobby come back there without a change of
-- place. Wait a moment so the client has loaded.
core.register_on_joinplayer(function(player)
	local player_name = player:get_player_name()
	core.after(2, function()
		if core.get_player_by_name(player_name) then
			update(player_name, lep_places.get_place(player_name))
		end
	end)
end)

core.register_on_leaveplayer(function(player)
	update(player:get_player_name(), nil)
end)
