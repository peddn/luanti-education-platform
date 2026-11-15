local hall = dofile("mods/lep_lobby/src/hall.lua")

local R, H = hall.RADIUS, hall.WALL_HEIGHT

local function each_position(callback)
	local min, max = hall.bounds()
	for x = min.x - 1, max.x + 1 do
		for y = min.y - 1, max.y + 1 do
			for z = min.z - 1, max.z + 1 do
				callback(x, y, z)
			end
		end
	end
end

describe("lep_lobby hall shape", function()
	it("has air in the middle and a glass pane below it", function()
		assert.are.equal(hall.AIR, hall.kind_at(0, 1, 0))
		assert.are.equal(hall.GLASS, hall.kind_at(0, 0, 0))
	end)

	it("has a solid floor around the glass pane", function()
		assert.are.equal(hall.GLASS, hall.kind_at(hall.GLASS_FLOOR_RADIUS, 0, 0))
		assert.are.equal(hall.FLOOR, hall.kind_at(hall.GLASS_FLOOR_RADIUS + 1, 0, 0))
		assert.are.equal(hall.FLOOR, hall.kind_at(R, 0, 0))
		assert.are.equal(hall.FLOOR, hall.kind_at(R + 1, 0, 0))
	end)

	it("has the usable space reach the inner radius", function()
		assert.are.equal(hall.AIR, hall.kind_at(R, 1, 0))
		assert.are.equal(hall.AIR, hall.kind_at(0, 1, -R))
		assert.are.not_equal(hall.AIR, hall.kind_at(R + 1, 1, 0))
	end)

	it("has a wall of glass or lamps around the usable space", function()
		for y = 1, H do
			local kind = hall.kind_at(R + 1, y, 0)
			assert.is_true(kind == hall.GLASS or kind == hall.LAMP)
		end
		assert.are.equal(hall.GLASS, hall.kind_at(R + 1, 2, 0))
	end)

	it("is as high as wall plus dome in the middle", function()
		assert.are.equal(hall.AIR, hall.kind_at(0, H + R, 0))
		assert.are.equal(hall.LAMP, hall.kind_at(0, H + R + 1, 0))
		assert.is_nil(hall.kind_at(0, H + R + 2, 0))
	end)

	it("has nothing outside its bounds", function()
		local min, max = hall.bounds()
		each_position(function(x, y, z)
			local outside = x < min.x or x > max.x or y < min.y or y > max.y
				or z < min.z or z > max.z
			if outside then
				assert.is_nil(hall.kind_at(x, y, z))
			end
		end)
	end)

	it("is symmetric in x and z", function()
		each_position(function(x, y, z)
			local kind = hall.kind_at(x, y, z)
			-- Lamps are snapped to a grid of directions and need not mirror.
			local function solid(k)
				return k == hall.LAMP and hall.GLASS or k
			end
			assert.are.equal(solid(kind), solid(hall.kind_at(-x, y, z)))
			assert.are.equal(solid(kind), solid(hall.kind_at(x, y, -z)))
			assert.are.equal(solid(kind), solid(hall.kind_at(z, y, x)))
		end)
	end)

	it("is closed: the air inside never touches the outside", function()
		-- Flood fill through air from the middle. It must never step onto
		-- a position that is outside the hall.
		local seen = {}
		local queue = { { 0, 1, 0 } }
		local head = 1
		local neighbours = {
			{ 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 },
		}
		local air_count = 0
		while queue[head] do
			local x, y, z = queue[head][1], queue[head][2], queue[head][3]
			head = head + 1
			local id = x .. "," .. y .. "," .. z
			if not seen[id] then
				seen[id] = true
				local kind = hall.kind_at(x, y, z)
				assert.is_not_nil(kind, "air leaks out at " .. id)
				if kind == hall.AIR then
					air_count = air_count + 1
					for _, n in ipairs(neighbours) do
						queue[#queue + 1] = { x + n[1], y + n[2], z + n[3] }
					end
				end
			end
		end
		assert.is_true(air_count > 1000)
	end)

	it("places lamps only in the shell", function()
		local count = 0
		each_position(function(x, y, z)
			if hall.kind_at(x, y, z) == hall.LAMP then
				count = count + 1
				assert.is_true(y >= 1)
			end
		end)
		assert.are.equal(hall.lamp_count(), count)
	end)

	it("has a ring of lamps at the foot of the wall and lamps in the dome", function()
		local foot, dome = 0, 0
		each_position(function(x, y, z)
			if hall.kind_at(x, y, z) == hall.LAMP then
				if y == 1 then
					foot = foot + 1
				elseif y > H then
					dome = dome + 1
				end
			end
		end)
		assert.is_true(foot >= 12)
		assert.is_true(dome >= 15)
	end)

	it("keeps every floor position near a lamp or the portal", function()
		-- Light drops by one per node. With the portal glowing in the middle
		-- and lamps at the wall, no walkable spot may be far from a source.
		local sources = { { 0, 1, 0 } }
		each_position(function(x, y, z)
			if hall.kind_at(x, y, z) == hall.LAMP and y == 1 then
				sources[#sources + 1] = { x, y, z }
			end
		end)
		for x = -R, R do
			for z = -R, R do
				if hall.kind_at(x, 1, z) == hall.AIR then
					local nearest = math.huge
					for _, s in ipairs(sources) do
						local d = math.abs(x - s[1]) + math.abs(z - s[3])
						nearest = math.min(nearest, d)
					end
					assert.is_true(nearest <= 8, "dark spot at " .. x .. "," .. z)
				end
			end
		end
	end)
end)

describe("lep_lobby hall anchors", function()
	local origin = { x = 256, y = 9000, z = 256 }
	local anchors = hall.anchors(origin)

	local function relative(pos)
		return pos.x - origin.x, pos.y - origin.y, pos.z - origin.z
	end

	it("puts the spawn point on the floor inside the hall", function()
		local x, y, z = relative(anchors.spawn)
		assert.are.equal(hall.AIR, hall.kind_at(x, y, z))
		assert.are.equal(hall.AIR, hall.kind_at(x, y + 1, z))
		assert.are.equal(hall.FLOOR, hall.kind_at(x, y - 1, z))
	end)

	it("puts the portal in the middle on the glass pane", function()
		local x, y, z = relative(anchors.portal)
		assert.are.same({ 0, 1, 0 }, { x, y, z })
		assert.are.equal(hall.GLASS, hall.kind_at(x, y - 1, z))
	end)

	it("starts the corridor just outside the wall", function()
		local x, y, z = relative(anchors.corridor_start)
		assert.is_nil(hall.kind_at(x, y, z))
		assert.is_not_nil(hall.kind_at(x - anchors.corridor_dir.x, y, z))
		assert.are.same({ x = 1, y = 0, z = 0 }, anchors.corridor_dir)
	end)

	it("protects the whole hall", function()
		local min, max = hall.bounds()
		assert.are.same(
			{ x = origin.x + min.x, y = origin.y + min.y, z = origin.z + min.z },
			anchors.protect_min)
		assert.are.same(
			{ x = origin.x + max.x, y = origin.y + max.y, z = origin.z + max.z },
			anchors.protect_max)
	end)
end)
