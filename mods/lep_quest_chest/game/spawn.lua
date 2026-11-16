-- Lets chests appear near the players in the wilderness.

local load = lep_core.loader("lep_quest_chest")
local chests = load("src/chests")
local world = load("game/chests")
local S = core.get_translator("lep_quest_chest")

-- Seconds between two rounds through the players.
local ROUND = 10
-- Seconds until the next try if no spot was found.
local RETRY = 30
-- How many random spots are tried per round.
local TRIES = 20
-- The column that is searched for the ground, relative to the player.
local ABOVE = 32
local BELOW = 24

local store = world.store

local DIRECTIONS = {
	n = S("north"), ne = S("north-east"), e = S("east"), se = S("south-east"),
	s = S("south"), sw = S("south-west"), w = S("west"), nw = S("north-west"),
}

-- Air and what a chest may replace: grass, flowers, a layer of snow.
local function is_free(name)
	if name == "air" then
		return true
	end
	local def = core.registered_nodes[name]
	return def ~= nil and def.buildable_to == true and def.liquidtype == "none"
end

-- Returns the position on the ground of a column, or nil if the column
-- has no suitable ground: water, a cave, a building, a protected plot,
-- or an area that was never generated.
--
-- The column is searched from above. Only air, plants and trees may lie
-- above the ground, so a spot is never in a cave or inside a house, but
-- it can be on the forest floor.
local function find_spot(x, z, around_y)
	local top, bottom = around_y + ABOVE, around_y - BELOW
	core.load_area({ x = x, y = bottom, z = z }, { x = x, y = top, z = z })
	local above_is_free = false
	for y = top, bottom, -1 do
		local name = core.get_node({ x = x, y = y, z = z }).name
		if name == "ignore" then
			return nil
		end
		local free = is_free(name)
		if not free and not chests.is_tree(core.registered_nodes[name]) then
			local spot = { x = x, y = y + 1, z = z }
			-- The chest needs free space, not the place of a trunk.
			if not above_is_free or not chests.is_ground(core.registered_nodes[name]) then
				return nil
			end
			if core.is_protected(spot, "") or store:has(spot) then
				return nil
			end
			return spot
		end
		above_is_free = free
	end
	return nil
end

--- Lets a chest appear 30 to 80 nodes from a position.
-- @return the position of the new chest, or nil if no spot was found
function lep_quest_chest.spawn_near(pos)
	local center = vector.round(pos)
	for _ = 1, TRIES do
		local dx, dz = chests.spawn_offset(math.random)
		local spot = find_spot(center.x + dx, center.z + dz, center.y)
		if spot and lep_quest_chest.place(spot, false) then
			return spot
		end
	end
	return nil
end

--- Returns the direction from one position to another as translated text,
-- for example "north-east".
function lep_quest_chest.describe_direction(from, to)
	return DIRECTIONS[chests.direction(to.x - from.x, to.z - from.z)]
end

-- Per player: the time of the next check.
local next_check = {}

local function check_player(player, now)
	local player_name = player:get_player_name()
	if lep_places.get_place(player_name) ~= lep_places.WILDERNESS then
		return
	end
	if not next_check[player_name] then
		next_check[player_name] = now + chests.SPAWN_INTERVAL
		return
	end
	if now < next_check[player_name] then
		return
	end
	next_check[player_name] = now + chests.SPAWN_INTERVAL

	local pos = player:get_pos()
	if not store:can_spawn() or store:has_nearby(pos, player_name) then
		return
	end
	local spot = lep_quest_chest.spawn_near(pos)
	if not spot then
		next_check[player_name] = now + RETRY
		return
	end
	core.chat_send_player(player_name, S("A task chest has appeared nearby, to the @1.",
		lep_quest_chest.describe_direction(pos, spot)))
end

local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < ROUND then
		return
	end
	timer = 0
	local now = os.time()
	for _, player in ipairs(core.get_connected_players()) do
		check_player(player, now)
	end
end)

core.register_on_leaveplayer(function(player)
	next_check[player:get_player_name()] = nil
end)
