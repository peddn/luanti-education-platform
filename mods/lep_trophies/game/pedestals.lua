-- The pedestals in the personal rooms: what stands on them and the window
-- to choose it.

local load = lep_core.loader("lep_trophies")
local trophies = load("src/trophies")
local S = core.get_translator("lep_trophies")
local formspec = lep_core.formspec

local FORM = "lep_trophies:pedestal"
-- Raise this when the pedestals in the lobby change, so they are set again.
local LOBBY_VERSION = 1

local storage = core.get_mod_storage()

--------------------------------------------------------------------------
-- Nodes in the room

-- Puts the pedestals of a room in place, with what stands on them.
local function set_room(room)
	local state = lep_trophies._get_state(room.owner)
	-- The handles of a cup run along the wall it stands at.
	local param2 = room.look_dir.x ~= 0 and 0 or 1

	for slot, pos in ipairs(room.pedestals) do
		local above = vector.offset(pos, 0, 1, 0)
		core.load_area(pos, above)

		core.set_node(pos, { name = lep_trophies.PEDESTAL })
		local meta = core.get_meta(pos)
		meta:set_string("owner", room.owner)
		meta:set_int("slot", slot)
		meta:mark_as_private({ "owner", "slot" })

		local def = lep_trophies.get_trophy(state.slots[slot] or "")
		if def then
			local node = def.node
			if not node or not core.registered_nodes[node] then
				node = lep_trophies.CUPS[def.material]
			end
			core.set_node(above, { name = node, param2 = param2 })
			local text = def.title
			if def.description ~= "" then
				text = text .. "\n" .. def.description
			end
			core.get_meta(above):set_string("infotext", text)
		else
			core.remove_node(above)
		end
	end
end

local function update_room(owner)
	local room = lep_lobby.get_room(owner)
	if room then
		set_room(room)
	end
end

lep_lobby.register_on_room_built(set_room)

-- Rooms that were built before this mod existed get their pedestals now.
core.register_on_mods_loaded(function()
	if storage:get_int("lobby_version") == LOBBY_VERSION then
		return
	end
	core.after(0, function()
		lep_lobby.when_ready(function()
			for _, room in ipairs(lep_lobby.get_rooms()) do
				set_room(room)
			end
			storage:set_int("lobby_version", LOBBY_VERSION)
		end)
	end)
end)

--------------------------------------------------------------------------
-- Window

-- What each player has open: the pedestal and the list as it was shown.
-- The answer of the client is only an index into this list.
local open = {}

local function show(player_name, slot, selected)
	local state = lep_trophies._get_state(player_name)
	local ids = lep_trophies.get_earned(player_name)
	local lines = {}
	for index, id in ipairs(ids) do
		local line = lep_trophies.get_trophy(id).title
		for other = 1, lep_trophies.SLOTS do
			if state.slots[other] == id then
				line = line .. "  " .. (other == slot and S("(stands here)")
					or S("(on pedestal @1)", other))
			end
		end
		lines[index] = line
	end

	-- Always tell the client which line is selected, so both sides agree:
	-- the trophy on this pedestal, otherwise the first line.
	if not selected or selected < 1 or selected > #ids then
		selected = nil
		for index, id in ipairs(ids) do
			if state.slots[slot] == id then
				selected = index
			end
		end
		if not selected and #ids > 0 then
			selected = 1
		end
	end
	open[player_name] = { slot = slot, ids = ids, selected = selected }

	local pad = formspec.PADDING
	local width, list_height = 9, 5
	local top = formspec.CONTENT_TOP
	local list_y = top + 0.5
	local button_y = list_y + list_height + 0.3
	local button_width = (width - 3 * pad - formspec.CLOSE_WIDTH - 0.2) / 2

	local fs = formspec.new(width, button_y + 0.8 + pad)
		:title(S("Pedestal @1 of @2", slot, lep_trophies.SLOTS))
	if #ids == 0 then
		fs:label(pad, top + 0.2, S("You have not earned any trophies yet."))
	else
		fs:label(pad, top + 0.2, S("Choose a trophy:"))
	end
	fs:textlist(pad, list_y, width - 2 * pad, list_height, "list", lines, selected)
		:button(pad, button_y, button_width, 0.8, "place", S("Put it here"))
		:button(pad + button_width + 0.2, button_y, button_width, 0.8, "clear", S("Clear pedestal"))
		:close(S("Close"))

	core.show_formspec(player_name, FORM, fs:build())
end

core.override_item(lep_trophies.PEDESTAL, {
	on_rightclick = function(pos, _, clicker, itemstack)
		if not clicker or not clicker:is_player() then
			return itemstack
		end
		local player_name = clicker:get_player_name()
		local meta = core.get_meta(pos)
		local owner = meta:get_string("owner")
		if player_name == owner then
			show(player_name, meta:get_int("slot"))
		else
			core.chat_send_player(player_name, S("This pedestal belongs to @1.", owner))
		end
		return itemstack
	end,
})

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= FORM then
		return false
	end
	local player_name = player:get_player_name()
	local context = open[player_name]
	if not context then
		-- No window of ours is open for this player: ignore what was sent.
		return true
	end

	if fields.list then
		local event = core.explode_textlist_event(fields.list)
		if event.type == "CHG" or event.type == "DCL" then
			context.selected = event.index
		end
		if event.type ~= "DCL" then
			return true
		end
	end

	local change = false
	local id
	if fields.clear then
		change = true
	elseif fields.place or fields.list then
		-- The pedestal and the trophy come from what the server showed,
		-- never from the client. The core checks again that it is earned.
		id = context.ids[context.selected or 0]
		change = id ~= nil
	end

	if change then
		local state, err = trophies.place(lep_trophies._get_state(player_name),
			context.slot, id, lep_trophies.SLOTS)
		if state then
			lep_trophies._set_state(player_name, state)
			update_room(player_name)
		else
			core.log("warning", "[lep_trophies] " .. player_name .. ": " .. tostring(err))
		end
		show(player_name, context.slot, context.selected)
		return true
	end

	if fields.quit then
		open[player_name] = nil
	end
	return true
end)

core.register_on_leaveplayer(function(player)
	open[player:get_player_name()] = nil
end)
