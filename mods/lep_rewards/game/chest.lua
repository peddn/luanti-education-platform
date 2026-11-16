-- The reward chest in every personal room.

local load = lep_core.loader("lep_rewards")
local inventory = load("game/inventory")
local S = core.get_translator("lep_rewards")
local formspec = lep_core.formspec

local CHEST = "lep_rewards:chest"
-- Raise this when the chests in the lobby change, so they are set again.
local LOBBY_VERSION = 1

local storage = core.get_mod_storage()

local function show(player_name)
	inventory.ensure(player_name)
	local pad = formspec.PADDING
	local width = formspec.slots(inventory.COLUMNS) + 2 * pad
	local chest_y = 1
	local player_y = chest_y + formspec.slots(inventory.ROWS) + 1.1
	local height = player_y + formspec.slots(4) + pad
	local location = "detached:" .. inventory.location(player_name)

	local fs = formspec.new(width, height)
		:label(pad, 0.5, S("Your rewards"))
		:list(location, inventory.LIST, pad, chest_y, inventory.COLUMNS, inventory.ROWS)

	local waiting = inventory.pending_count(player_name)
	if waiting > 0 then
		fs:label(pad, player_y - 0.5, S("@1 more are waiting until there is room.", waiting))
	end

	fs:list("current_player", "main", pad, player_y, 8, 4)
		:listring(location, inventory.LIST)
		:listring("current_player", "main")

	core.show_formspec(player_name, "lep_rewards:chest", fs:build())
end

-- The owner has the window open when they take something out. Show it
-- again, so the number of waiting rewards is up to date.
inventory.set_on_refilled(show)

core.register_node(CHEST, {
	description = "LEP reward chest",
	tiles = {
		"default_chest_top.png", "default_chest_top.png",
		"default_chest_side.png", "default_chest_side.png",
		"default_chest_side.png", "default_chest_front.png",
	},
	paramtype2 = "facedir",
	groups = { not_in_creative_inventory = 1 },
	sounds = default.node_sound_wood_defaults(),
	diggable = false,
	is_ground_content = false,
	drop = "",
	on_blast = function() end,
	can_dig = function() return false end,
	on_rightclick = function(pos, _, clicker, itemstack)
		if not clicker or not clicker:is_player() then
			return itemstack
		end
		local player_name = clicker:get_player_name()
		local owner = core.get_meta(pos):get_string("owner")
		if player_name == owner then
			show(player_name)
		else
			core.chat_send_player(player_name, S("This chest belongs to @1.", owner))
		end
		return itemstack
	end,
})

local function set_chest(room)
	core.load_area(room.chest, room.chest)
	core.set_node(room.chest, {
		name = CHEST,
		-- The front faces the door.
		param2 = core.dir_to_facedir({ x = room.look_dir.x, y = 0, z = room.look_dir.z }),
	})
	local meta = core.get_meta(room.chest)
	meta:set_string("owner", room.owner)
	meta:mark_as_private("owner")
end

lep_lobby.register_on_room_built(set_chest)

-- Rooms that were built before this mod existed get their chest now.
core.register_on_mods_loaded(function()
	if storage:get_int("lobby_version") == LOBBY_VERSION then
		return
	end
	core.after(0, function()
		lep_lobby.when_ready(function()
			for _, room in ipairs(lep_lobby.get_rooms()) do
				set_chest(room)
			end
			storage:set_int("lobby_version", LOBBY_VERSION)
		end)
	end)
end)
