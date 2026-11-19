-- State and rules of the task chests. Pure Lua, no engine calls.
--
-- A chest is known by its position. The store keeps for every chest when
-- it was set, whether it is permanent (set by a teacher) and who solved
-- it. Times are seconds as from os.time(), passed in by the caller.

local chests = {}

-- Seconds a spawned chest stays if nobody solves it.
chests.LIFETIME_UNSOLVED = 30 * 60
-- Seconds a spawned chest stays after it was solved for the first time,
-- so companions can solve it as well.
chests.LIFETIME_SOLVED = 10 * 60
-- Seconds a player waits after a wrong answer.
chests.RETRY_DELAY = 30
-- Most chests the world spawns at the same time.
chests.MAX_SPAWNED = 20
-- A new chest appears this far from the player, in nodes.
chests.SPAWN_MIN = 30
chests.SPAWN_MAX = 80
-- A chest within this distance counts as nearby: no new one is spawned.
chests.NEARBY = 80
-- Seconds between two checks whether a player needs a new chest.
chests.SPAWN_INTERVAL = 180
-- How far from a chest a player may stand to answer, in nodes.
chests.REACH = 6

--- Returns the key of a position, for example "12,5,-3".
function chests.key(pos)
	return pos.x .. "," .. pos.y .. "," .. pos.z
end

local function copy_pos(pos)
	return { x = pos.x, y = pos.y, z = pos.z }
end

local function is_pos(pos)
	return type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number"
		and type(pos.z) == "number"
end

--------------------------------------------------------------------------
-- Store

local Store = {}
Store.__index = Store

--- Creates a store, empty or from the table that Store:data returned.
-- Entries that cannot be read are dropped.
function chests.new_store(data)
	local store = setmetatable({ _chests = {} }, Store)
	if type(data) ~= "table" then
		return store
	end
	for _, entry in pairs(data) do
		if type(entry) == "table" and is_pos(entry.pos) and type(entry.created) == "number" then
			local solved = {}
			if type(entry.solved) == "table" then
				for name, value in pairs(entry.solved) do
					if type(name) == "string" and value == true then
						solved[name] = true
					end
				end
			end
			store._chests[chests.key(entry.pos)] = {
				pos = copy_pos(entry.pos),
				created = entry.created,
				permanent = entry.permanent == true,
				first_solved = type(entry.first_solved) == "number" and entry.first_solved
					or nil,
				solved = solved,
			}
		end
	end
	return store
end

--- Returns a plain table with everything, for saving.
function Store:data()
	local data = {}
	for _, chest in pairs(self._chests) do
		local solved = {}
		for name in pairs(chest.solved) do
			solved[name] = true
		end
		data[#data + 1] = {
			pos = copy_pos(chest.pos),
			created = chest.created,
			permanent = chest.permanent,
			first_solved = chest.first_solved,
			solved = solved,
		}
	end
	table.sort(data, function(a, b)
		return chests.key(a.pos) < chests.key(b.pos)
	end)
	return data
end

--- Forgets which chests a player solved. For an account that is removed.
-- @return true if the player had solved any
function Store:forget(player_name)
	local known = false
	for _, chest in pairs(self._chests) do
		if chest.solved[player_name] then
			chest.solved[player_name] = nil
			known = true
		end
	end
	return known
end

--- Adds a chest. Returns false if there already is one at this position.
function Store:add(pos, now, permanent)
	local key = chests.key(pos)
	if self._chests[key] then
		return false
	end
	self._chests[key] = {
		pos = copy_pos(pos),
		created = now,
		permanent = permanent == true,
		solved = {},
	}
	return true
end

--- Returns true if there is a chest at this position.
function Store:has(pos)
	return self._chests[chests.key(pos)] ~= nil
end

--- Returns true if the chest at this position was set by a teacher.
function Store:is_permanent(pos)
	local chest = self._chests[chests.key(pos)]
	return chest ~= nil and chest.permanent
end

--- Removes a chest. Returns true if there was one.
function Store:remove(pos)
	local key = chests.key(pos)
	if not self._chests[key] then
		return false
	end
	self._chests[key] = nil
	return true
end

--- Returns the positions of all chests, sorted by key.
function Store:positions()
	local list = {}
	for _, chest in pairs(self._chests) do
		list[#list + 1] = copy_pos(chest.pos)
	end
	table.sort(list, function(a, b)
		return chests.key(a) < chests.key(b)
	end)
	return list
end

--- Returns how many chests the world spawned, without those of teachers.
function Store:count_spawned()
	local count = 0
	for _, chest in pairs(self._chests) do
		if not chest.permanent then
			count = count + 1
		end
	end
	return count
end

--- Returns true if the world may spawn another chest.
function Store:can_spawn()
	return self:count_spawned() < chests.MAX_SPAWNED
end

--- Returns true if this player solved the chest at this position.
function Store:has_solved(pos, player_name)
	local chest = self._chests[chests.key(pos)]
	return chest ~= nil and chest.solved[player_name] == true
end

--- Notes that a player solved a chest. Returns false if there is no
-- chest or the player solved it before.
function Store:mark_solved(pos, player_name, now)
	local chest = self._chests[chests.key(pos)]
	if not chest or chest.solved[player_name] then
		return false
	end
	chest.solved[player_name] = true
	chest.first_solved = chest.first_solved or now
	return true
end

--- Returns the time a chest disappears, or nil for a permanent chest or
-- an unknown position.
function Store:expires_at(pos)
	local chest = self._chests[chests.key(pos)]
	if not chest or chest.permanent then
		return nil
	end
	local unsolved = chest.created + chests.LIFETIME_UNSOLVED
	if not chest.first_solved then
		return unsolved
	end
	-- Solving a chest never makes it stay longer than it would have.
	return math.min(unsolved, chest.first_solved + chests.LIFETIME_SOLVED)
end

--- Returns the positions of the chests whose time is up.
function Store:expired(now)
	local list = {}
	for _, pos in ipairs(self:positions()) do
		local expires = self:expires_at(pos)
		if expires and now >= expires then
			list[#list + 1] = pos
		end
	end
	return list
end

--- Makes all spawned chests older by a number of seconds, as if time
-- had passed. For trying out in the test world.
function Store:age(seconds)
	for _, chest in pairs(self._chests) do
		if not chest.permanent then
			chest.created = chest.created - seconds
			if chest.first_solved then
				chest.first_solved = chest.first_solved - seconds
			end
		end
	end
end

--- Returns true if a chest stands near a position, so this player needs
-- no new one. Only the horizontal distance counts. A permanent chest the
-- player already solved does not count: it would keep new chests away
-- from this place for ever.
function Store:has_nearby(pos, player_name)
	for _, chest in pairs(self._chests) do
		local dx, dz = chest.pos.x - pos.x, chest.pos.z - pos.z
		if dx * dx + dz * dz <= chests.NEARBY * chests.NEARBY
				and not (chest.permanent and chest.solved[player_name]) then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------
-- Attempts

-- What a player is doing at a chest: the task they were given, or the
-- time until which they wait after a wrong answer. Kept in memory only.

local Attempts = {}
Attempts.__index = Attempts

--- Creates an empty list of attempts.
function chests.new_attempts()
	return setmetatable({ _by_player = {} }, Attempts)
end

local function entry(self, player_name, pos, create)
	local by_chest = self._by_player[player_name]
	if not by_chest then
		if not create then
			return nil
		end
		by_chest = {}
		self._by_player[player_name] = by_chest
	end
	local key = chests.key(pos)
	if not by_chest[key] and create then
		by_chest[key] = { tries = 0 }
	end
	return by_chest[key]
end

--- Returns how many seconds a player still has to wait at a chest, 0 if
-- they may answer.
function Attempts:wait_left(player_name, pos, now)
	local current = entry(self, player_name, pos)
	if not current or not current.locked_until then
		return 0
	end
	return math.max(0, current.locked_until - now)
end

--- Returns the task a player has at a chest, or nil.
function Attempts:get_task(player_name, pos)
	local current = entry(self, player_name, pos)
	return current and current.task
end

--- Remembers the task a player was given at a chest.
function Attempts:set_task(player_name, pos, task)
	entry(self, player_name, pos, true).task = task
end

--- Notes a wrong answer: the task is gone and the player waits.
-- @return the number of wrong answers at this chest so far
function Attempts:fail(player_name, pos, now)
	local current = entry(self, player_name, pos, true)
	current.task = nil
	current.tries = current.tries + 1
	current.locked_until = now + chests.RETRY_DELAY
	return current.tries
end

--- Returns how many wrong answers a player gave at a chest.
function Attempts:tries(player_name, pos)
	local current = entry(self, player_name, pos)
	return current and current.tries or 0
end

--- Forgets everything about a chest, for all players.
function Attempts:forget_chest(pos)
	local key = chests.key(pos)
	for _, by_chest in pairs(self._by_player) do
		by_chest[key] = nil
	end
end

--------------------------------------------------------------------------
-- Spawning

--- Returns true if a player standing at `player_pos` is close enough to
-- the chest at `pos` to answer.
function chests.in_reach(player_pos, pos)
	local dx, dy, dz = player_pos.x - pos.x, player_pos.y - pos.y, player_pos.z - pos.z
	return dx * dx + dy * dy + dz * dz <= chests.REACH * chests.REACH
end

--- Returns a random horizontal offset for a new chest, as dx, dz, between
-- SPAWN_MIN and SPAWN_MAX nodes away.
-- @param random Function(min, max) returning a whole number in that range.
function chests.spawn_offset(random)
	local angle = math.rad(random(0, 359))
	local distance = random(chests.SPAWN_MIN, chests.SPAWN_MAX)
	local function round(value)
		return math.floor(value + 0.5)
	end
	return round(math.cos(angle) * distance), round(math.sin(angle) * distance)
end

-- The eight directions of the compass, counter-clockwise from east.
local DIRECTIONS = { "e", "ne", "n", "nw", "w", "sw", "s", "se" }

--- Returns the direction of a horizontal offset as "n", "ne", "e", "se",
-- "s", "sw", "w" or "nw". North is +z and east is +x, as in the game.
function chests.direction(dx, dz)
	local angle = math.atan2(dz, dx)
	local index = math.floor(angle / (math.pi / 4) + 0.5) % 8
	return DIRECTIONS[index + 1]
end

-- Ground a chest may stand on, by node group.
local GROUND_GROUPS = { "soil", "sand", "stone", "snowy" }

--- Returns true if a chest may stand on a node with this definition:
-- solid natural ground, no liquid, no leaves, nothing built.
-- @param def Table with walkable, liquidtype and groups, as in the
--   engine's node definitions. nil for an unknown node.
function chests.is_ground(def)
	if type(def) ~= "table" or def.walkable == false then
		return false
	end
	if def.liquidtype ~= nil and def.liquidtype ~= "none" then
		return false
	end
	local groups = def.groups or {}
	for _, group in ipairs(GROUND_GROUPS) do
		if (groups[group] or 0) > 0 then
			return true
		end
	end
	return false
end

--- Returns true if a node with this definition is part of a tree: leaves
-- or trunk. The search for the ground looks through trees, so chests can
-- stand on the forest floor.
function chests.is_tree(def)
	if type(def) ~= "table" then
		return false
	end
	local groups = def.groups or {}
	return (groups.leaves or 0) > 0 or (groups.tree or 0) > 0
end

return chests
