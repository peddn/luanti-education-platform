-- Shape of the generated lobby hall. Pure Lua, no engine calls.
--
-- The hall is a glass cylinder with a glass dome on top. The floor is solid
-- with a round glass pane in the middle. Lamps sit at the foot of the wall
-- and in the dome. All coordinates here are relative to the hall origin:
-- the centre of the floor, with the floor itself at y = 0.

local hall = {}

-- Inner radius of the hall.
hall.RADIUS = 10
-- Height of the vertical wall below the dome.
hall.WALL_HEIGHT = 4
-- Radius of the glass pane in the floor.
hall.GLASS_FLOOR_RADIUS = 3
-- Raise this when the shape changes, so existing halls are rebuilt.
hall.VERSION = 1

-- Node kinds returned by hall.kind_at.
hall.FLOOR = "floor"
hall.GLASS = "glass"
hall.LAMP = "lamp"
hall.AIR = "air"

local R = hall.RADIUS
local H = hall.WALL_HEIGHT

local function key(x, y, z)
	return x .. "," .. y .. "," .. z
end

local function round(value)
	return math.floor(value + 0.5)
end

-- "inside" means inside the usable space, "shell" the one node thick skin.
local function classify(distance)
	if distance < R + 0.5 then
		return "inside"
	elseif distance < R + 1.5 then
		return "shell"
	end
	return "outside"
end

local function region(x, y, z)
	if y <= H then
		return classify(math.sqrt(x * x + z * z))
	end
	local dy = y - H
	return classify(math.sqrt(x * x + dy * dy + z * z))
end

-- Lamp positions: a ring at the foot of the wall and three rings in the
-- dome, plus one at the top. Each wanted direction is snapped to the
-- nearest shell node.
local function build_lamps()
	local lamps = {}

	local function add_ring(count, elevation_deg)
		local elevation = math.rad(elevation_deg)
		for i = 0, count - 1 do
			local angle = 2 * math.pi * i / count
			local horizontal = (R + 1) * math.cos(elevation)
			local x = round(horizontal * math.cos(angle))
			local z = round(horizontal * math.sin(angle))
			local y = H + round((R + 1) * math.sin(elevation))
			if region(x, y, z) == "shell" then
				lamps[key(x, y, z)] = true
			end
		end
	end

	-- Foot of the wall.
	for i = 0, 15 do
		local angle = 2 * math.pi * i / 16
		local x = round((R + 1) * math.cos(angle))
		local z = round((R + 1) * math.sin(angle))
		if region(x, 1, z) == "shell" then
			lamps[key(x, 1, z)] = true
		end
	end

	add_ring(12, 25)
	add_ring(8, 50)
	add_ring(4, 72)
	lamps[key(0, H + R + 1, 0)] = true

	return lamps
end

local lamps = build_lamps()

--- Returns the lowest and highest relative coordinates of the hall.
function hall.bounds()
	return { x = -(R + 1), y = 0, z = -(R + 1) },
		{ x = R + 1, y = H + R + 1, z = R + 1 }
end

--- Returns what belongs at a position relative to the origin:
-- hall.FLOOR, hall.GLASS, hall.LAMP, hall.AIR, or nil outside the hall.
function hall.kind_at(x, y, z)
	if y < 0 then
		return nil
	end

	if y == 0 then
		local distance = math.sqrt(x * x + z * z)
		if distance >= R + 1.5 then
			return nil
		elseif distance < hall.GLASS_FLOOR_RADIUS + 0.5 then
			return hall.GLASS
		end
		return hall.FLOOR
	end

	local where = region(x, y, z)
	if where == "outside" then
		return nil
	elseif where == "inside" then
		return hall.AIR
	elseif lamps[key(x, y, z)] then
		return hall.LAMP
	end
	return hall.GLASS
end

--- Returns the number of lamps.
function hall.lamp_count()
	local count = 0
	for _ in pairs(lamps) do
		count = count + 1
	end
	return count
end

--- Returns the important spots of the hall in world coordinates.
-- A hand-built hall has to provide the same table.
-- @param origin World position of the centre of the floor.
-- @return Table with:
--   spawn           where arriving players stand
--   portal          where the fixed portal goes, on the glass pane
--   corridor_start  first node of the corridor outside the wall
--   corridor_dir    direction of the corridor, a unit vector
--   protect_min, protect_max  the area nobody may change
function hall.anchors(origin)
	local min, max = hall.bounds()
	return {
		spawn = { x = origin.x, y = origin.y + 1, z = origin.z - (R - 3) },
		portal = { x = origin.x, y = origin.y + 1, z = origin.z },
		corridor_start = { x = origin.x + R + 2, y = origin.y + 1, z = origin.z },
		corridor_dir = { x = 1, y = 0, z = 0 },
		protect_min = { x = origin.x + min.x, y = origin.y + min.y, z = origin.z + min.z },
		protect_max = { x = origin.x + max.x, y = origin.y + max.y, z = origin.z + max.z },
	}
end

return hall
