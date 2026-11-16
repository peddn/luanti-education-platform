local frames = dofile("mods/lep_portals/src/frames.lua")

local function key(pos)
	return pos.x .. "," .. pos.y .. "," .. pos.z
end

-- A little world: a set of frame nodes and a set of other solid nodes.
local function world()
	local w = { frame = {}, solid = {} }
	function w.is_frame(pos)
		return w.frame[key(pos)] == true
	end
	function w.is_free(pos)
		return not w.frame[key(pos)] and not w.solid[key(pos)]
	end
	function w.build(base, axis, with_corners)
		for _, pos in ipairs(frames.required(base, axis)) do
			w.frame[key(pos)] = true
		end
		if with_corners then
			for _, pos in ipairs(frames.corners(base, axis)) do
				w.frame[key(pos)] = true
			end
		end
	end
	return w
end

local BASE = { x = 10, y = 5, z = -3 }

describe("lep_portals frames", function()
	it("has a field of two nodes and a frame of six plus four corners", function()
		for _, axis in ipairs(frames.AXES) do
			assert.are.same({ BASE, { x = 10, y = 6, z = -3 } }, frames.field(BASE, axis))
			assert.are.equal(6, #frames.required(BASE, axis))
			assert.are.equal(4, #frames.corners(BASE, axis))
		end
		-- All twelve positions are different and form a 3 x 4 wall.
		local seen, count = {}, 0
		for _, list in ipairs({
			frames.field(BASE, "x"), frames.required(BASE, "x"), frames.corners(BASE, "x"),
		}) do
			for _, pos in ipairs(list) do
				assert.is_nil(seen[key(pos)])
				seen[key(pos)] = true
				count = count + 1
				assert.are.equal(BASE.z, pos.z)
				assert.is_true(math.abs(pos.x - BASE.x) <= 1)
				assert.is_true(pos.y >= BASE.y - 1 and pos.y <= BASE.y + 2)
			end
		end
		assert.are.equal(12, count)
	end)

	for _, axis in ipairs(frames.AXES) do
		for _, with_corners in ipairs({ false, true }) do
			local label = "along " .. axis .. (with_corners and " with corners" or " without corners")

			it("finds a portal from every frame node, " .. label, function()
				local w = world()
				w.build(BASE, axis, with_corners)
				local clicked = frames.required(BASE, axis)
				if with_corners then
					for _, pos in ipairs(frames.corners(BASE, axis)) do
						clicked[#clicked + 1] = pos
					end
				end
				for _, pos in ipairs(clicked) do
					local base, found_axis = frames.find(pos, w.is_frame, w.is_free)
					assert.are.same(BASE, base)
					assert.are.equal(axis, found_axis)
				end
			end)
		end
	end

	it("finds nothing when a required frame node is missing", function()
		for index = 1, 6 do
			local w = world()
			w.build(BASE, "x", true)
			local missing = frames.required(BASE, "x")[index]
			w.frame[key(missing)] = nil
			assert.is_false(frames.is_complete(BASE, "x", w.is_frame))
			for _, pos in ipairs(frames.required(BASE, "x")) do
				if w.is_frame(pos) then
					local base, reason = frames.find(pos, w.is_frame, w.is_free)
					assert.is_nil(base)
					assert.are.equal(frames.NO_FRAME, reason)
				end
			end
		end
	end)

	it("reports a blocked inside", function()
		local w = world()
		w.build(BASE, "z", false)
		w.solid[key(frames.field(BASE, "z")[2])] = true
		local base, reason = frames.find(frames.required(BASE, "z")[1], w.is_frame, w.is_free)
		assert.is_nil(base)
		assert.are.equal(frames.BLOCKED, reason)
	end)

	it("does not take a lying frame for a portal", function()
		local w = world()
		-- The same ring of nodes, but flat on the ground.
		for _, pos in ipairs(frames.required(BASE, "x")) do
			w.frame[key({ x = pos.x, y = BASE.y, z = BASE.z + (pos.y - BASE.y) })] = true
		end
		local base = frames.find({ x = BASE.x - 1, y = BASE.y, z = BASE.z }, w.is_frame, w.is_free)
		assert.is_nil(base)
	end)

	it("lets players arrive one step in front of the portal", function()
		assert.are.same({ x = 10, y = 5, z = -2 }, frames.arrival(BASE, "x", 1))
		assert.are.same({ x = 10, y = 5, z = -4 }, frames.arrival(BASE, "x", -1))
		assert.are.same({ x = 11, y = 5, z = -3 }, frames.arrival(BASE, "z", 1))
		for _, axis in ipairs(frames.AXES) do
			for _, side in ipairs({ 1, -1 }) do
				local arrival = frames.arrival(BASE, axis, side)
				assert.are.equal(side, frames.side_of(BASE, axis, arrival))
				for _, pos in ipairs(frames.field(BASE, axis)) do
					assert.are.not_same(pos, arrival)
				end
			end
		end
	end)

	it("describes a portal with arrival point and signs", function()
		local portal = frames.portal({ x = 10, y = 5, z = 20 }, "x", -1,
			{ distance = 2, signs = "both" })
		assert.are.same({ x = 10, y = 5, z = 20 }, portal.base)
		assert.are.equal("x", portal.axis)
		assert.are.same({ x = 10, y = 5, z = 18 }, portal.arrival)
		assert.are.same({ x = 0, y = 0, z = -1 }, portal.look_dir)
		-- Front sign first, then the one on the back.
		assert.are.same({ pos = { x = 10, y = 7, z = 19 }, wall = { x = 0, y = 0, z = 1 } },
			portal.signs[1])
		assert.are.same({ pos = { x = 10, y = 7, z = 21 }, wall = { x = 0, y = 0, z = -1 } },
			portal.signs[2])
	end)

	it("describes a portal along the other axis", function()
		local portal = frames.portal({ x = -3, y = 1, z = 6 }, "z", 1, { signs = "front" })
		assert.are.same({ x = -2, y = 1, z = 6 }, portal.arrival)
		assert.are.same({ x = 1, y = 0, z = 0 }, portal.look_dir)
		assert.are.equal(1, #portal.signs)
		assert.are.same({ pos = { x = -2, y = 3, z = 6 }, wall = { x = -1, y = 0, z = 0 } },
			portal.signs[1])
	end)

	it("hangs every sign on the top node of the frame", function()
		for _, axis in ipairs({ "x", "z" }) do
			local base = { x = 4, y = 9, z = -2 }
			local portal = frames.portal(base, axis, 1, { signs = "both" })
			for _, sign in ipairs(portal.signs) do
				assert.are.same({ x = base.x, y = base.y + 2, z = base.z }, {
					x = sign.pos.x + sign.wall.x, y = sign.pos.y, z = sign.pos.z + sign.wall.z })
			end
		end
	end)

	it("describes a portal without signs by default", function()
		local portal = frames.portal({ x = 0, y = 0, z = 0 }, "x", 1)
		assert.are.same({}, portal.signs)
		assert.are.same({ x = 0, y = 0, z = 1 }, portal.arrival)
		assert.has_error(function() frames.portal({ x = 0, y = 0, z = 0 }, "y", 1) end)
		assert.has_error(function() frames.portal({ x = 0, y = 0, z = 0 }, "x", 0) end)
	end)

	it("lists all nodes of a portal", function()
		assert.are.equal(12, #frames.nodes({ x = 0, y = 0, z = 0 }, "x"))
	end)
end)
