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
end)
