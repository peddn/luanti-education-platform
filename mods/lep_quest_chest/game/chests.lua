-- The chest node and the list of all chests in the world.

local load = lep_core.loader("lep_quest_chest")
local chests = load("src/chests")
local storage = load("game/storage")
local S = core.get_translator("lep_quest_chest")

local NODE = "lep_quest_chest:chest"
local PRIVILEGE = "lep_place_quest_chest"
-- Seconds between two checks for chests whose time is up.
local EXPIRY_INTERVAL = 5

local store = chests.new_store(storage.load())

local function save()
	storage.save(store:data())
end

local M = { store = store, save = save }

local on_rightclick = function() end
local on_removed = function() end

--- Sets the function(player_name, pos) called when a player right-clicks
-- a chest. The window registers itself here.
function M.set_on_rightclick(callback)
	on_rightclick = callback
end

--- Sets the function(pos) called after a chest was removed.
function M.set_on_removed(callback)
	on_removed = callback
end

core.register_privilege(PRIVILEGE, {
	description = "Can place and remove task chests",
	give_to_singleplayer = false,
	give_to_admin = true,
})

lep_quest_chest.NODE = NODE
lep_quest_chest.PRIVILEGE = PRIVILEGE

--- Returns true if a player may place and remove task chests.
function lep_quest_chest.may_manage(player_name)
	return core.check_player_privs(player_name, { [PRIVILEGE] = true })
end

--- Sets a task chest at a position.
-- @param permanent True for a chest that never disappears by itself, as
--   teachers place them. Chests spawned by the world are not permanent.
-- @return true, or false if there already is a chest
function lep_quest_chest.place(pos, permanent)
	pos = vector.round(pos)
	if not store:add(pos, os.time(), permanent) then
		return false
	end
	save()
	core.load_area(pos, pos)
	core.set_node(pos, { name = NODE, param2 = math.random(0, 3) })
	core.log("action", "[lep_quest_chest] " .. (permanent and "permanent " or "")
		.. "chest set at " .. core.pos_to_string(pos))
	return true
end

--- Removes the task chest at a position.
-- @return true, or false if there is none
function lep_quest_chest.remove(pos)
	pos = vector.round(pos)
	if not store:remove(pos) then
		return false
	end
	save()
	core.load_area(pos, pos)
	if core.get_node(pos).name == NODE then
		core.remove_node(pos)
	end
	core.log("action", "[lep_quest_chest] chest removed at " .. core.pos_to_string(pos))
	on_removed(pos)
	return true
end

--- Returns the positions of all task chests.
function lep_quest_chest.get_positions()
	return store:positions()
end

local MARK = "^lep_quest_chest_mark.png"

core.register_node(NODE, {
	description = S("Task chest"),
	tiles = {
		"default_chest_top.png" .. MARK, "default_chest_top.png",
		"default_chest_side.png" .. MARK, "default_chest_side.png" .. MARK,
		"default_chest_side.png" .. MARK, "default_chest_front.png" .. MARK,
	},
	paramtype2 = "facedir",
	-- A faint glow, so the chest can be found at night.
	light_source = 8,
	groups = { not_in_creative_inventory = 1 },
	sounds = default.node_sound_wood_defaults(),
	-- Nobody digs a task chest. Teachers remove it through its window.
	diggable = false,
	is_ground_content = false,
	drop = "",
	on_blast = function() end,
	can_dig = function() return false end,

	on_place = function(itemstack, placer, pointed_thing)
		if not placer or not placer:is_player() then
			return itemstack
		end
		local player_name = placer:get_player_name()
		if not lep_quest_chest.may_manage(player_name) then
			core.chat_send_player(player_name, S("You may not place task chests."))
			return itemstack
		end
		return core.item_place(itemstack, placer, pointed_thing)
	end,

	-- Only chests placed by hand come through here: they are permanent.
	after_place_node = function(pos, placer)
		store:add(pos, os.time(), true)
		save()
		core.log("action", "[lep_quest_chest] "
			.. (placer and placer:get_player_name() or "?")
			.. " placed a permanent chest at " .. core.pos_to_string(pos))
	end,

	on_rightclick = function(pos, _, clicker, itemstack)
		if clicker and clicker:is_player() then
			on_rightclick(clicker:get_player_name(), pos)
		end
		return itemstack
	end,
})

-- A chest node the list does not know, for example after the list was
-- lost, would stand there for ever. It is removed when its area loads.
core.register_lbm({
	label = "Remove unknown task chests",
	name = "lep_quest_chest:remove_unknown",
	nodenames = { NODE },
	run_at_every_load = true,
	action = function(pos)
		if not store:has(pos) then
			core.remove_node(pos)
			core.log("action", "[lep_quest_chest] removed unknown chest at "
				.. core.pos_to_string(pos))
		end
	end,
})

-- Spawned chests disappear when their time is up.
local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < EXPIRY_INTERVAL then
		return
	end
	timer = 0
	for _, pos in ipairs(store:expired(os.time())) do
		lep_quest_chest.remove(pos)
	end
end)

-- An account that is removed is forgotten at every chest it solved.
lep_core.register_on_forget_account(function(account)
	if store:forget(account) then
		save()
	end
end)

return M
