-- The learning hall: a straight gallery with one portal per learning
-- module. Pure Lua, no engine calls.
--
-- The hall is reached through a portal in the lobby and grows with the
-- number of modules. All coordinates are relative to its origin: the
-- floor node at the middle of the south wall. The gallery runs north
-- (+z). At its south end stands the portal back to the lobby, the module
-- portals stand along both side walls.

local learning = {}

-- Half the inner width: the interior spans x from -HALF_WIDTH to it.
learning.HALF_WIDTH = 3
-- Inner height.
learning.HEIGHT = 5
-- z of the first pair of module portals.
learning.FIRST = 6
-- Distance between two pairs of module portals.
learning.PITCH = 5
-- The hall always has room for this many pairs, so it never looks cut
-- off.
learning.MIN_ROWS = 2
-- Raise this when the shape changes, so the hall is rebuilt.
learning.VERSION = 1

-- Node kinds returned by learning.kind_at.
learning.FLOOR = "floor"
learning.WALL = "wall"
learning.LAMP = "lamp"
learning.AIR = "air"

local W = learning.HALF_WIDTH

--- Returns the number of pairs of portals the hall is built for.
function learning.rows(count)
	return math.max(learning.MIN_ROWS, math.ceil(count / 2))
end

--- Returns the inner length of a hall with `count` module portals.
function learning.length(count)
	return learning.FIRST + (learning.rows(count) - 1) * learning.PITCH + 3
end

--- Returns the lowest and highest relative coordinates of the hall,
-- shell included.
function learning.bounds(count)
	return { x = -(W + 1), y = 0, z = 0 },
		{ x = W + 1, y = learning.HEIGHT + 1, z = learning.length(count) + 1 }
end

--- Returns what belongs at a relative position: learning.FLOOR, WALL,
-- LAMP or AIR, or nil outside the hall.
function learning.kind_at(x, y, z, count)
	local min, max = learning.bounds(count)
	if x < min.x or x > max.x or y < min.y or y > max.y or z < min.z or z > max.z then
		return nil
	end
	local on_row = z >= learning.FIRST and (z - learning.FIRST) % learning.PITCH == 0
		and z < max.z
	if y == min.y then
		-- A lamp in the floor between every pair of portals.
		return (x == 0 and on_row) and learning.LAMP or learning.FLOOR
	elseif y == max.y then
		return (x == 0 and on_row) and learning.LAMP or learning.WALL
	elseif x == min.x or x == max.x or z == min.z or z == max.z then
		return learning.WALL
	end
	return learning.AIR
end

--- Returns the portal back to the lobby:
--   base, axis  as in src/frames.lua
--   arrival     where players stand who come into the hall
--   look_dir    the direction they look in, into the hall
--   sign        where its sign hangs
--   sign_wall   direction from the sign to the node it hangs on
function learning.exit()
	return {
		base = { x = 0, y = 1, z = 1 },
		axis = "x",
		arrival = { x = 0, y = 1, z = 3 },
		look_dir = { x = 0, y = 0, z = 1 },
		sign = { x = 0, y = 3, z = 2 },
		sign_wall = { x = 0, y = 0, z = -1 },
	}
end

--- Returns the module portal of a slot, counted from 0. Even slots stand
-- at the west wall, odd slots at the east wall. Fields as in
-- learning.exit; `arrival` is where a player stands in front of it, and
-- `look_dir` points from there into the hall, away from the portal.
function learning.portal(slot)
	assert(type(slot) == "number" and slot >= 0 and slot == math.floor(slot),
		"slot must be a whole number from 0")
	local side = slot % 2 == 0 and -1 or 1
	local z = learning.FIRST + math.floor(slot / 2) * learning.PITCH
	return {
		base = { x = side * W, y = 1, z = z },
		axis = "z",
		arrival = { x = side * (W - 1), y = 1, z = z },
		look_dir = { x = -side, y = 0, z = 0 },
		sign = { x = side * (W - 1), y = 3, z = z },
		sign_wall = { x = side, y = 0, z = 0 },
	}
end

--- Returns the two portals in the lobby hall, in world coordinates. They
-- stand side by side where the hall has its place for a portal: the one
-- to the wilderness on the west, the one to the learning hall on the
-- east. Players arrive south of them.
-- @param anchor The hall's place for a portal: the lower field node of a
--   portal that would stand there alone.
-- @return Table with `wilderness` and `learning`, each with base, axis,
--   arrival, look_dir, sign and sign_wall as in learning.exit.
function learning.hub(anchor)
	local function portal(dx)
		local base = { x = anchor.x + dx, y = anchor.y, z = anchor.z }
		return {
			base = base,
			axis = "x",
			arrival = { x = base.x, y = base.y, z = base.z - 2 },
			look_dir = { x = 0, y = 0, z = -1 },
			sign = { x = base.x, y = base.y + 2, z = base.z - 1 },
			sign_wall = { x = 0, y = 0, z = 1 },
		}
	end
	return { wilderness = portal(-2), learning = portal(2) }
end

--------------------------------------------------------------------------
-- Slots

-- Which module has which portal. A module keeps its slot for good, so its
-- portal stays where the students know it, whatever else is installed
-- later.

local Slots = {}
Slots.__index = Slots

--- Creates the record, empty or from the table that Slots:export
-- returned.
function learning.new_slots(data)
	local slots = setmetatable({ _by_id = {}, _count = 0 }, Slots)
	if type(data) == "table" then
		local taken = {}
		for id, slot in pairs(data) do
			if type(id) == "string" and type(slot) == "number" and slot >= 0
					and slot == math.floor(slot) and not taken[slot] then
				slots._by_id[id] = slot
				taken[slot] = true
				slots._count = math.max(slots._count, slot + 1)
			end
		end
	end
	return slots
end

--- Returns the slot of a module and assigns the next free one if it has
-- none yet. The second value is true if the slot is new.
function Slots:assign(id)
	assert(type(id) == "string" and id ~= "", "id must be a non-empty string")
	if self._by_id[id] then
		return self._by_id[id], false
	end
	local slot = self._count
	self._by_id[id] = slot
	self._count = slot + 1
	return slot, true
end

--- Returns the slot of a module, or nil.
function Slots:get(id)
	return self._by_id[id]
end

--- Returns how many slots the hall has to offer room for.
function Slots:count()
	return self._count
end

--- Returns a plain table for storage.
function Slots:export()
	local copy = {}
	for id, slot in pairs(self._by_id) do
		copy[id] = slot
	end
	return copy
end

return learning
