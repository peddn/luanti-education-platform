-- Doors of the personal rooms. They use the door mechanics of Minetest
-- Game, with their own rule about who may open them.

local load = lep_core.loader("lep_lobby")
local corridors = load("src/corridors")
local S = core.get_translator("lep_lobby")

local DOOR = "lep_lobby:room_door"

local room_doors = {}

doors.register(DOOR, {
	description = "LEP lobby room door",
	tiles = { { name = "doors_door_wood.png", backface_culling = true } },
	inventory_image = "doors_item_wood.png",
	groups = { not_in_creative_inventory = 1 },
	protected = true,
	sounds = default.node_sound_wood_defaults(),
})

local function is_staff(player_name)
	return core.check_player_privs(player_name, { protection_bypass = true })
end

local function on_rightclick(pos, node, clicker, itemstack)
	if not clicker or not clicker:is_player() then
		return itemstack
	end
	local player_name = clicker:get_player_name()
	local owner = core.get_meta(pos):get_string("owner")
	local room = lep_lobby.get_room(owner)
	local feet = vector.round(clicker:get_pos())
	local inside = room ~= nil
		and feet.x >= room.interior_min.x and feet.x <= room.interior_max.x
		and feet.y >= room.interior_min.y and feet.y <= room.interior_max.y
		and feet.z >= room.interior_min.z and feet.z <= room.interior_max.z

	-- Minetest Game stores an odd state number for an open door.
	local is_open = core.get_meta(pos):get_int("state") % 2 == 1

	local allowed = corridors.may_use_door(
		player_name == owner, is_staff(player_name), inside, is_open)
	if allowed then
		-- Without a player the door skips its own owner check.
		doors.door_toggle(pos, node, nil)
	else
		core.chat_send_player(player_name, S("This door is not yours."))
	end
	return itemstack
end

-- Minetest Game registers one node per hinge side and state.
for _, suffix in ipairs({ "_a", "_b", "_c", "_d" }) do
	local name = DOOR .. suffix
	if core.registered_nodes[name] then
		core.override_item(name, {
			on_rightclick = on_rightclick,
			diggable = false,
			can_dig = function() return false end,
			on_blast = function() end,
			drop = "",
		})
	end
end

--- Returns true if the node name is one of the room doors.
function room_doors.is_door(node_name)
	return node_name:sub(1, #DOOR + 1) == DOOR .. "_"
end

--- Makes sure a room has its door. An existing door is left alone, so it
-- keeps being open or closed. A new door starts open.
-- @param pos Position of the lower half.
-- @param look_dir Direction from the corridor into the room, { x, z }.
function room_doors.ensure(pos, look_dir, owner)
	if room_doors.is_door(core.get_node(pos).name) then
		return
	end
	local facedir = core.dir_to_facedir({ x = look_dir.x, y = 0, z = look_dir.z })
	core.set_node(pos, { name = DOOR .. "_a", param2 = facedir })
	core.set_node(vector.offset(pos, 0, 1, 0), { name = "doors:hidden", param2 = facedir })
	local meta = core.get_meta(pos)
	meta:set_int("state", 0)
	meta:set_string("owner", owner)
	doors.door_toggle(pos, nil, nil)
end

return room_doors
