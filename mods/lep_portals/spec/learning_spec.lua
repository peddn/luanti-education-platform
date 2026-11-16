local learning = dofile("mods/lep_portals/src/learning.lua")
local frames = dofile("mods/lep_portals/src/frames.lua")
learning.use_frames(frames)

describe("lep_portals learning hall", function()
	it("has room for at least two pairs of portals", function()
		assert.are.equal(2, learning.rows(0))
		assert.are.equal(2, learning.rows(4))
		assert.are.equal(3, learning.rows(5))
		assert.are.equal(learning.length(0), learning.length(4))
		assert.is_true(learning.length(5) > learning.length(4))
	end)

	it("grows by one pitch for every further pair", function()
		assert.are.equal(learning.PITCH, learning.length(6) - learning.length(4))
		assert.are.equal(learning.length(7), learning.length(8))
	end)

	it("is closed all around", function()
		local count = 3
		local min, max = learning.bounds(count)
		for x = min.x, max.x do
			for y = min.y, max.y do
				for z = min.z, max.z do
					local kind = learning.kind_at(x, y, z, count)
					local on_shell = x == min.x or x == max.x or y == min.y or y == max.y
						or z == min.z or z == max.z
					if on_shell then
						assert.is_true(kind == learning.FLOOR or kind == learning.WALL
							or kind == learning.LAMP)
					else
						assert.are.equal(learning.AIR, kind)
					end
				end
			end
		end
		assert.is_nil(learning.kind_at(min.x - 1, 1, 1, count))
		assert.is_nil(learning.kind_at(0, max.y + 1, 1, count))
		assert.is_nil(learning.kind_at(0, 1, max.z + 1, count))
	end)

	it("has lamps in floor and ceiling between the portals", function()
		assert.are.equal(learning.LAMP, learning.kind_at(0, 0, learning.FIRST, 2))
		assert.are.equal(learning.LAMP,
			learning.kind_at(0, learning.HEIGHT + 1, learning.FIRST + learning.PITCH, 2))
		assert.are.equal(learning.FLOOR, learning.kind_at(1, 0, learning.FIRST, 2))
		assert.are.equal(learning.FLOOR, learning.kind_at(0, 0, learning.FIRST + 1, 2))
	end)

	-- Every node of a portal and the spot in front of it has to be inside.
	local function assert_fits(portal, count)
		local nodes = frames.nodes(portal.base, portal.axis)
		nodes[#nodes + 1] = portal.arrival
		for _, sign in ipairs(portal.signs) do
			nodes[#nodes + 1] = sign.pos
		end
		for _, pos in ipairs(nodes) do
			local kind = learning.kind_at(pos.x, pos.y, pos.z, count)
			-- The lowest frame row sits in the floor.
			assert.is_true(kind == learning.AIR or (pos.y == 0 and kind == learning.FLOOR),
				"node outside the interior at " .. pos.x .. "," .. pos.y .. "," .. pos.z)
		end
	end

	it("fits the exit portal into the south end", function()
		local exit = learning.exit()
		assert_fits(exit, 0)
		assert.are.equal("x", exit.axis)
		assert.are.same({ x = 0, y = 1, z = 3 }, exit.arrival)
		assert.are.same({ x = 0, y = 0, z = 1 }, exit.look_dir)
		assert.are.equal(1, #exit.signs)
	end)

	it("puts module portals alternately at the west and the east wall", function()
		local first, second, third = learning.portal(0), learning.portal(1), learning.portal(2)
		assert.are.equal(-learning.HALF_WIDTH, first.base.x)
		assert.are.equal(learning.HALF_WIDTH, second.base.x)
		assert.are.equal(first.base.z, second.base.z)
		assert.are.equal(first.base.z + learning.PITCH, third.base.z)
		assert.are.equal("z", first.axis)
		assert.are.same({ x = 1, y = 0, z = 0 }, first.look_dir)
		assert.are.same({ x = -1, y = 0, z = 0 }, second.look_dir)
	end)

	it("fits every module portal into the hall built for it", function()
		for count = 1, 9 do
			for slot = 0, count - 1 do
				assert_fits(learning.portal(slot), count)
			end
		end
	end)

	it("keeps portals clear of each other and of the exit", function()
		local used = {}
		local function claim(portal)
			local nodes = frames.nodes(portal.base, portal.axis)
			nodes[#nodes + 1] = portal.arrival
			for _, pos in ipairs(nodes) do
				local key = pos.x .. "," .. pos.y .. "," .. pos.z
				assert.is_nil(used[key], "two portals share " .. key)
				used[key] = true
			end
		end
		claim(learning.exit())
		for slot = 0, 7 do
			claim(learning.portal(slot))
		end
	end)

	it("puts two portals side by side in the lobby hall", function()
		local hub = learning.hub({ x = 100, y = 50, z = 200 })
		assert.are.same({ x = 98, y = 50, z = 200 }, hub.wilderness.base)
		assert.are.same({ x = 102, y = 50, z = 200 }, hub.learning.base)
		-- The frames are three wide: one node stays free between them.
		assert.are.equal(4, hub.learning.base.x - hub.wilderness.base.x)
		assert.are.same({ x = 102, y = 50, z = 198 }, hub.learning.arrival)
		assert.are.same({ x = 0, y = 0, z = -1 }, hub.learning.look_dir)
		assert.are.equal("x", hub.wilderness.axis)
		-- A sign on the front and one on the back.
		assert.are.same({ x = 102, y = 52, z = 199 }, hub.learning.signs[1].pos)
		assert.are.same({ x = 102, y = 52, z = 201 }, hub.learning.signs[2].pos)
		assert.are.equal(2, #hub.wilderness.signs)
	end)

	it("rejects slots that are none", function()
		assert.has_error(function() learning.portal(-1) end)
		assert.has_error(function() learning.portal(1.5) end)
	end)
end)

describe("lep_portals learning slots", function()
	it("assigns slots in the order modules ask", function()
		local slots = learning.new_slots()
		assert.are.same({ 0, true }, { slots:assign("math") })
		assert.are.same({ 1, true }, { slots:assign("quiz") })
		assert.are.same({ 0, false }, { slots:assign("math") })
		assert.are.equal(2, slots:count())
		assert.are.equal(1, slots:get("quiz"))
		assert.is_nil(slots:get("logic"))
	end)

	it("keeps slots after saving and loading, whatever the order", function()
		local slots = learning.new_slots()
		slots:assign("math")
		slots:assign("quiz")
		local copy = learning.new_slots(slots:export())
		assert.are.same({ 2, true }, { copy:assign("logic") })
		assert.are.same({ 1, false }, { copy:assign("quiz") })
		assert.are.same({ 0, false }, { copy:assign("math") })
	end)

	it("keeps the slot of a module that is not installed any more", function()
		local slots = learning.new_slots({ math = 0, gone = 1 })
		assert.are.same({ 2, true }, { slots:assign("quiz") })
		assert.are.equal(3, slots:count())
	end)

	it("drops stored entries it cannot read", function()
		local slots = learning.new_slots({ math = 0, twice = 0, bad = -1, half = 1.5,
			[5] = 2, text = "x" })
		assert.are.equal(1, slots:count())
		assert.are.same({}, learning.new_slots("broken"):export())
	end)

	it("rejects ids that are none", function()
		assert.has_error(function() learning.new_slots():assign("") end)
	end)
end)
