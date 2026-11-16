-- Public API of lep_attention: starting and ending the mode.

local load = lep_core.loader("lep_attention")
local attention = load("src/attention")
local effects = load("game/effects")

local STORAGE_KEY = "attention"
local mod_storage = core.get_mod_storage()
local list = attention.new(core.deserialize(mod_storage:get_string(STORAGE_KEY)))

local function save()
	mod_storage:set_string(STORAGE_KEY, core.serialize(list:data()))
end

--- Returns true if a player is in the attention mode.
function lep_attention.is_active(player_name)
	return list:is_active(player_name)
end

-- Brings an online player back to where the mode took them from.
local function bring_back(player_name)
	local origin = list:take_origin(player_name)
	save()
	effects.remove(player_name)
	if not origin then
		return
	end
	local ok, err = lep_places.move(player_name, origin.place, origin.pos)
	if not ok then
		core.log("warning", "[lep_attention] cannot bring " .. player_name .. " back to "
			.. origin.place .. ": " .. tostring(err))
		lep_places.move_back(player_name)
		return
	end
	-- A student the teacher had sent into a learning room is held there
	-- again.
	if origin.held then
		lep_rooms.hold(player_name)
	end
end

--- Starts the attention mode for an online player, or changes the text
-- for a player who is in it.
-- @param text Text of the teacher, or nil for the default.
-- @return true  or  false, error message
function lep_attention.start(player_name, text)
	local player = core.get_player_by_name(player_name)
	if not player then
		return false, "player '" .. tostring(player_name) .. "' is not online"
	end
	text = attention.clean_text(text)

	local needs_move = list:start(player_name, {
		place = lep_places.get_place(player_name),
		pos = player:get_pos(),
		held = lep_rooms.is_held(player_name),
	}, text)
	save()
	if not needs_move then
		effects.apply(player_name, text)
		return true
	end

	-- The screen goes black at once, the cell follows.
	effects.apply(player_name, text)
	lep_rooms.enter(player_name, lep_attention.ROOM_TYPE, function(ok, err)
		if ok then
			core.log("action", "[lep_attention] " .. player_name .. " is in the attention mode")
		else
			core.log("error", "[lep_attention] no cell for " .. player_name .. ": "
				.. tostring(err))
			list:stop(player_name)
			list:take_origin(player_name)
			save()
			effects.remove(player_name)
		end
		lep_desk.refresh()
	end)
	return true
end

--- Ends the attention mode for a player. An online player comes back to
-- where they were; an offline player comes back when they join again.
-- @return true if the player was in the mode
function lep_attention.stop(player_name)
	if not list:stop(player_name) then
		return false
	end
	save()
	core.log("action", "[lep_attention] the attention mode of " .. player_name .. " has ended")
	if core.get_player_by_name(player_name) then
		bring_back(player_name)
	end
	lep_desk.refresh()
	return true
end

local function stop_all()
	-- Without a teacher nobody is held, so nobody is held again either.
	list:forget_holds()
	save()
	for _, player_name in ipairs(list:active_names()) do
		lep_attention.stop(player_name)
	end
end

-- The mode never outlasts the teacher. After a start of the server no
-- teacher is online.
lep_desk.register_on_unattended(stop_all)
core.register_on_mods_loaded(stop_all)

-- The cell has no exit, and a student in the mode can use no commands,
-- so nothing holds them there but the walls. If something else takes a
-- student out, for example the teacher sending them into a learning room,
-- the mode ends where they are.
lep_places.register_on_place_changed(function(player_name, old_place)
	if old_place ~= lep_attention.PLACE or not list:is_active(player_name) then
		return
	end
	list:stop(player_name)
	list:take_origin(player_name)
	save()
	effects.remove(player_name)
	core.log("action", "[lep_attention] " .. player_name
		.. " was taken out of the cell, the attention mode has ended")
	lep_desk.refresh()
end)

-- A student in the mode who joins again is still in it. One whose mode
-- ended while they were away comes back now.
core.register_on_joinplayer(function(player)
	local player_name = player:get_player_name()
	if list:is_active(player_name) then
		lep_chat.set_deaf(player_name, true)
	end
	-- After the other mods have set up the player.
	core.after(0.5, function()
		if not core.get_player_by_name(player_name) then
			return
		end
		if list:is_active(player_name) then
			effects.apply(player_name, list:get_text(player_name))
		elseif list:awaits_return(player_name) then
			bring_back(player_name)
		elseif lep_places.get_place(player_name) == lep_attention.PLACE then
			-- In a cell without a way back on record.
			lep_places.move_back(player_name)
		end
	end)
end)
