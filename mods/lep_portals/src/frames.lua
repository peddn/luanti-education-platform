-- Shape of a portal. Pure Lua, no engine calls.
--
-- A portal stands upright. Its field is one node wide and two nodes high.
-- The frame around it is three wide and four high. The four corners of
-- the frame are optional.
--
-- A portal is described by its "base", the position of the lower field
-- node, and its "axis": "x" if the frame runs along x, "z" if along z.
-- Players walk through it across the axis.

local frames = {}

frames.AXES = { "x", "z" }

-- Reasons why no portal was found.
frames.NO_FRAME = "no_frame"
frames.BLOCKED = "blocked"

local function offset(base, axis, along, up)
	return {
		x = base.x + (axis == "x" and along or 0),
		y = base.y + up,
		z = base.z + (axis == "z" and along or 0),
	}
end

-- { along, up } relative to the base.
local FIELD = { { 0, 0 }, { 0, 1 } }
local REQUIRED = { { 0, -1 }, { 0, 2 }, { -1, 0 }, { -1, 1 }, { 1, 0 }, { 1, 1 } }
local CORNERS = { { -1, -1 }, { 1, -1 }, { -1, 2 }, { 1, 2 } }

local function positions(list, base, axis)
	local result = {}
	for index, entry in ipairs(list) do
		result[index] = offset(base, axis, entry[1], entry[2])
	end
	return result
end

--- Returns the two field positions of a portal, lower one first.
function frames.field(base, axis)
	return positions(FIELD, base, axis)
end

--- Returns the six frame positions a portal needs.
function frames.required(base, axis)
	return positions(REQUIRED, base, axis)
end

--- Returns the four optional corner positions.
function frames.corners(base, axis)
	return positions(CORNERS, base, axis)
end

--- Returns true if all six required frame positions hold a frame node.
-- @param is_frame Function(pos) returning true for a frame node.
function frames.is_complete(base, axis, is_frame)
	for _, pos in ipairs(frames.required(base, axis)) do
		if not is_frame(pos) then
			return false
		end
	end
	return true
end

--- Finds the portal that a frame node belongs to.
-- @param clicked Position of a frame node.
-- @param is_frame Function(pos) returning true for a frame node.
-- @param is_free Function(pos) returning true if a field node fits there.
-- @return base, axis  or  nil, frames.NO_FRAME / frames.BLOCKED
function frames.find(clicked, is_frame, is_free)
	local blocked = false
	for _, axis in ipairs(frames.AXES) do
		for _, list in ipairs({ REQUIRED, CORNERS }) do
			for _, entry in ipairs(list) do
				-- If the clicked node sits at this spot of the frame, the
				-- base is here:
				local base = offset(clicked, axis, -entry[1], -entry[2])
				if frames.is_complete(base, axis, is_frame) then
					local field = frames.field(base, axis)
					if is_free(field[1]) and is_free(field[2]) then
						return base, axis
					end
					blocked = true
				end
			end
		end
	end
	return nil, blocked and frames.BLOCKED or frames.NO_FRAME
end

--- Returns where a player arrives: one step in front of the portal.
-- @param side 1 or -1, the side of the portal.
function frames.arrival(base, axis, side)
	return {
		x = base.x + (axis == "z" and side or 0),
		y = base.y,
		z = base.z + (axis == "x" and side or 0),
	}
end

--- Describes a whole portal: where it stands, where players arrive and
-- where its signs hang. Everything that sets or uses a portal works with
-- this table.
-- @param base, axis As above.
-- @param side 1 or -1: the side players arrive on, its front.
-- @param options Optional table with:
--   distance  how many steps in front of the portal players arrive,
--             default 1
--   signs     "front" for a sign above the opening on the front,
--             "both" for one on each side, nil for none
-- @return Table with
--   base, axis, side
--   arrival   where arriving players stand
--   look_dir  the direction they look in, away from the portal
--   signs     list of { pos, wall }: where a sign hangs and the direction
--             from there to the frame node it hangs on
function frames.portal(base, axis, side, options)
	assert(axis == "x" or axis == "z", "axis must be 'x' or 'z'")
	assert(side == 1 or side == -1, "side must be 1 or -1")
	options = options or {}
	local distance = options.distance or 1

	-- One step across the frame, towards the given side.
	local function across(steps)
		return {
			x = base.x + (axis == "z" and steps or 0),
			y = base.y,
			z = base.z + (axis == "x" and steps or 0),
		}
	end

	local function sign(on_side)
		local pos = across(on_side)
		-- Above the opening, on the top of the frame.
		pos.y = base.y + 2
		return {
			pos = pos,
			wall = { x = axis == "z" and -on_side or 0, y = 0, z = axis == "x" and -on_side or 0 },
		}
	end

	local signs = {}
	if options.signs == "front" or options.signs == "both" then
		signs[#signs + 1] = sign(side)
	end
	if options.signs == "both" then
		signs[#signs + 1] = sign(-side)
	end

	return {
		base = { x = base.x, y = base.y, z = base.z },
		axis = axis,
		side = side,
		arrival = across(side * distance),
		look_dir = { x = axis == "z" and side or 0, y = 0, z = axis == "x" and side or 0 },
		signs = signs,
	}
end

--- Returns all nodes a portal occupies: field, frame and corners.
function frames.nodes(base, axis)
	local nodes = {}
	for _, list in ipairs({ FIELD, REQUIRED, CORNERS }) do
		for _, pos in ipairs(positions(list, base, axis)) do
			nodes[#nodes + 1] = pos
		end
	end
	return nodes
end

--- Returns the side (1 or -1) of the portal a position is on.
function frames.side_of(base, axis, pos)
	local across = axis == "x" and (pos.z - base.z) or (pos.x - base.x)
	return across < 0 and -1 or 1
end

return frames
