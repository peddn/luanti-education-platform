-- Shape of the generated lobby hall. Pure Lua, no engine calls.
--
-- The hall is a glass cylinder with a glass dome on top. The floor is solid
-- with a round glass pane in the middle. Two rings of lamps are set into
-- the floor: one around the glass pane and one without gaps below the
-- glass wall. Fireflies hover below the dome, butterflies further down.
-- All coordinates here are relative to the hall origin:
-- the centre of the floor, with the floor itself at y = 0.

local hall = {}

-- Inner radius of the hall.
hall.RADIUS = 15
-- Height of the vertical wall below the dome.
hall.WALL_HEIGHT = 4
-- Radius of the glass pane in the floor.
hall.GLASS_FLOOR_RADIUS = 5
-- Raise this when the shape changes, so existing halls are rebuilt.
hall.VERSION = 2

-- Node kinds returned by hall.kind_at.
hall.FLOOR = "floor"
hall.GLASS = "glass"
hall.LAMP = "lamp"
hall.AIR = "air"
hall.FIREFLY = "firefly"
hall.BUTTERFLY = "butterfly"

-- Number of butterfly colours. kind_at returns the colour as second value.
hall.BUTTERFLY_COLOURS = 3

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

-- Fireflies: rings below the dome and one at the top, each one node
-- inside the glass. Each wanted direction is snapped to the node grid.
local function build_fireflies()
	local fireflies = {}

	local function add(x, y, z)
		if region(x, y, z) == "inside" then
			fireflies[key(x, y, z)] = true
		end
	end

	local function add_ring(count, elevation_deg, offset)
		local elevation = math.rad(elevation_deg)
		for i = 0, count - 1 do
			local angle = 2 * math.pi * (i + offset) / count
			local horizontal = (R - 1) * math.cos(elevation)
			add(round(horizontal * math.cos(angle)),
				H + round((R - 1) * math.sin(elevation)),
				round(horizontal * math.sin(angle)))
		end
	end

	add_ring(16, 18, 0)
	add_ring(12, 38, 0.5)
	add_ring(8, 58, 0)
	add_ring(4, 76, 0.5)
	add(0, H + R - 1, 0)

	return fireflies
end

-- Butterflies: a fixed spiral above head height, so the hall looks the
-- same after every rebuild.
local function build_butterflies(fireflies)
	local butterflies = {}
	local golden_angle = math.pi * (3 - math.sqrt(5))
	local count = 14
	for i = 1, count do
		local distance = 3 + (R - 5) * math.sqrt(i / count)
		local angle = i * golden_angle
		local x = round(distance * math.cos(angle))
		local z = round(distance * math.sin(angle))
		local y = 3 + (i * 2) % 5
		local id = key(x, y, z)
		if region(x, y, z) == "inside" and not fireflies[id] then
			butterflies[id] = (i % hall.BUTTERFLY_COLOURS) + 1
		end
	end
	return butterflies
end

local fireflies = build_fireflies()
local butterflies = build_butterflies(fireflies)

--- Returns the lowest and highest relative coordinates of the hall.
function hall.bounds()
	return { x = -(R + 1), y = 0, z = -(R + 1) },
		{ x = R + 1, y = H + R + 1, z = R + 1 }
end

--- Returns what belongs at a position relative to the origin:
-- hall.FLOOR, hall.GLASS, hall.LAMP, hall.AIR, hall.FIREFLY,
-- hall.BUTTERFLY (with the colour number as second value), or nil outside
-- the hall.
function hall.kind_at(x, y, z)
	if y < 0 then
		return nil
	end

	if y == 0 then
		local distance = math.sqrt(x * x + z * z)
		if distance >= R + 1.5 then
			return nil
		elseif distance >= R + 0.5 then
			-- Ring of light below the glass wall.
			return hall.LAMP
		elseif distance < hall.GLASS_FLOOR_RADIUS + 0.5 then
			return hall.GLASS
		elseif distance < hall.GLASS_FLOOR_RADIUS + 1.5 then
			-- Ring of light around the glass pane.
			return hall.LAMP
		end
		return hall.FLOOR
	end

	local where = region(x, y, z)
	if where == "outside" then
		return nil
	elseif where == "shell" then
		return hall.GLASS
	end

	local id = key(x, y, z)
	if fireflies[id] then
		return hall.FIREFLY
	elseif butterflies[id] then
		return hall.BUTTERFLY, butterflies[id]
	end
	return hall.AIR
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
