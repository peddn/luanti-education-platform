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

local function is_open(kind)
	return kind == hall.AIR or kind == hall.FIREFLY or kind == hall.BUTTERFLY
end

describe("lep_lobby hall shape", function()
	it("has air in the middle and a glass pane below it", function()
		assert.are.equal(hall.AIR, hall.kind_at(0, 1, 0))
		assert.are.equal(hall.GLASS, hall.kind_at(0, 0, 0))
	end)

	it("has a ring of light around the glass pane, then solid floor", function()
		local g = hall.GLASS_FLOOR_RADIUS
		assert.are.equal(hall.GLASS, hall.kind_at(g, 0, 0))
		assert.are.equal(hall.LAMP, hall.kind_at(g + 1, 0, 0))
		assert.are.equal(hall.FLOOR, hall.kind_at(g + 2, 0, 0))
		assert.are.equal(hall.FLOOR, hall.kind_at(R, 0, 0))
	end)

	it("has a ring of light without gaps below the glass wall", function()
		local min, max = hall.bounds()
		local count = 0
		for x = min.x, max.x do
			for z = min.z, max.z do
				local above = hall.kind_at(x, 1, z)
				local below = hall.kind_at(x, 0, z)
				if above == hall.GLASS then
					assert.are.equal(hall.LAMP, below, "gap at " .. x .. "," .. z)
					count = count + 1
				elseif is_open(above) then
					assert.is_true(below == hall.FLOOR or below == hall.GLASS
						or (below == hall.LAMP
							and math.sqrt(x * x + z * z) < hall.GLASS_FLOOR_RADIUS + 1.5))
				end
			end
		end
		assert.is_true(count >= 80)
	end)

	it("has the usable space reach the inner radius", function()
		assert.is_true(is_open(hall.kind_at(R, 1, 0)))
		assert.is_true(is_open(hall.kind_at(0, 1, -R)))
		assert.is_false(is_open(hall.kind_at(R + 1, 1, 0)))
	end)

	it("has wall and dome made of glass only", function()
		for y = 1, H do
			assert.are.equal(hall.GLASS, hall.kind_at(R + 1, y, 0))
		end
		each_position(function(x, y, z)
			if y >= 1 then
				assert.are.not_equal(hall.LAMP, hall.kind_at(x, y, z))
				assert.are.not_equal(hall.FLOOR, hall.kind_at(x, y, z))
			end
		end)
	end)

	it("is as high as wall plus dome in the middle", function()
		assert.are.equal(hall.AIR, hall.kind_at(0, H + R, 0))
		assert.are.equal(hall.GLASS, hall.kind_at(0, H + R + 1, 0))
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

	it("has a symmetric shell in x and z", function()
		-- Fireflies and butterflies are decoration and need not mirror.
		local function shell(kind)
			return is_open(kind) and hall.AIR or kind
		end
		each_position(function(x, y, z)
			local kind = shell(hall.kind_at(x, y, z))
			assert.are.equal(kind, shell(hall.kind_at(-x, y, z)))
			assert.are.equal(kind, shell(hall.kind_at(x, y, -z)))
			assert.are.equal(kind, shell(hall.kind_at(z, y, x)))
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
		local open_count = 0
		while queue[head] do
			local x, y, z = queue[head][1], queue[head][2], queue[head][3]
			head = head + 1
			local id = x .. "," .. y .. "," .. z
			if not seen[id] then
				seen[id] = true
				local kind = hall.kind_at(x, y, z)
				assert.is_not_nil(kind, "air leaks out at " .. id)
				if is_open(kind) then
					open_count = open_count + 1
					for _, n in ipairs(neighbours) do
						queue[#queue + 1] = { x + n[1], y + n[2], z + n[3] }
					end
				end
			end
		end
		assert.is_true(open_count > 5000)
	end)

	it("has fireflies below the dome, above the wall", function()
		local count = 0
		each_position(function(x, y, z)
			if hall.kind_at(x, y, z) == hall.FIREFLY then
				count = count + 1
				assert.is_true(y > H)
			end
		end)
		assert.is_true(count >= 35)
	end)

	it("has butterflies of every colour above head height", function()
		local colours = {}
		local count = 0
		each_position(function(x, y, z)
			local kind, colour = hall.kind_at(x, y, z)
			if kind == hall.BUTTERFLY then
				count = count + 1
				colours[colour] = true
				assert.is_true(y >= 3 and y <= 7)
			end
		end)
		assert.is_true(count >= 10)
		for colour = 1, hall.BUTTERFLY_COLOURS do
			assert.is_true(colours[colour])
		end
	end)

	it("keeps every floor position near a ring of light or the portal", function()
		-- Light drops by one per node. No walkable spot may be far from a
		-- lamp in the floor or from the glowing portal in the middle.
		local sources = { { 0, 1, 0 } }
		local min, max = hall.bounds()
		for x = min.x, max.x do
			for z = min.z, max.z do
				if hall.kind_at(x, 0, z) == hall.LAMP then
					sources[#sources + 1] = { x, 0, z }
				end
			end
		end
		for x = -R, R do
			for z = -R, R do
				if is_open(hall.kind_at(x, 1, z)) then
					local nearest = math.huge
					for _, s in ipairs(sources) do
						local d = math.abs(x - s[1]) + math.abs(1 - s[2]) + math.abs(z - s[3])
						nearest = math.min(nearest, d)
					end
					assert.is_true(nearest <= 7, "dark spot at " .. x .. "," .. z)
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
		assert.are.equal(hall.AIR, hall.kind_at(x, y + 2, z))
		assert.are.equal(hall.FLOOR, hall.kind_at(x, y - 1, z))
	end)

	it("puts the portal in the middle on the glass pane", function()
		local x, y, z = relative(anchors.portal)
		assert.are.same({ 0, 1, 0 }, { x, y, z })
		assert.are.equal(hall.GLASS, hall.kind_at(x, y - 1, z))
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
