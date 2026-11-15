local hall = dofile("mods/lep_lobby/src/hall.lua")
local corridors = dofile("mods/lep_lobby/src/corridors.lua")

local function is_open(kind)
	return kind == hall.AIR or kind == hall.FIREFLY or kind == hall.BUTTERFLY
		or kind == corridors.SIGN or kind == corridors.DOOR or kind == corridors.DOOR_TOP
end

-- The lobby as it is built: corridors first, the hall everywhere else.
local function kind_at(x, y, z, count)
	local kind = corridors.kind_at(x, y, z, count)
	if kind then
		return kind
	end
	return (hall.kind_at(x, y, z))
end

describe("lep_lobby corridors slots", function()
	it("fits the hall", function()
		assert.are.equal(hall.RADIUS + 1, corridors.OPENING)
	end)

	it("fills the four corridors evenly", function()
		local seen = {}
		for slot = 0, 31 do
			local direction, side, row = corridors.slot_position(slot)
			local id = direction .. ":" .. side .. ":" .. row
			assert.is_nil(seen[id])
			seen[id] = true
			assert.are.equal(math.floor(slot / 8), row)
		end
		for direction = 1, 4 do
			assert.are.equal(4, corridors.rows(direction, 32))
		end
	end)

	it("grows a corridor only when it gets a room", function()
		assert.are.equal(0, corridors.rows(1, 0))
		assert.are.equal(1, corridors.rows(1, 1))
		assert.are.equal(0, corridors.rows(2, 1))
		assert.are.equal(1, corridors.rows(4, 4))
		assert.are.equal(1, corridors.rows(1, 8))
		assert.are.equal(2, corridors.rows(1, 9))
		assert.are.equal(1, corridors.rows(2, 9))
	end)

	it("keeps a class of 30 within a short walk", function()
		for direction = 1, 4 do
			local _, max = corridors.bounds(direction, 30)
			local min = corridors.bounds(direction, 30)
			local reach = math.max(math.abs(min.x), math.abs(min.z),
				math.abs(max.x), math.abs(max.z))
			assert.is_true(reach - hall.RADIUS <= 30)
		end
	end)
end)

describe("lep_lobby corridors shape", function()
	it("opens the hall wall in all four directions", function()
		for _, pos in ipairs({ { 16, 0 }, { 0, 16 }, { -16, 0 }, { 0, -16 } }) do
			for y = 1, corridors.HEIGHT do
				assert.are.equal(hall.GLASS, hall.kind_at(pos[1], y, pos[2]))
				assert.are.equal(corridors.AIR, corridors.kind_at(pos[1], y, pos[2], 0))
			end
			assert.is_nil(corridors.kind_at(pos[1], corridors.HEIGHT + 1, pos[2], 0))
			-- The ring of light below the wall stays closed.
			assert.is_nil(corridors.kind_at(pos[1], 0, pos[2], 0))
		end
	end)

	it("never changes the inside of the hall", function()
		for x = -hall.RADIUS, hall.RADIUS do
			for z = -hall.RADIUS, hall.RADIUS do
				if is_open(hall.kind_at(x, 1, z)) then
					for y = 0, 6 do
						assert.is_nil(corridors.kind_at(x, y, z, 40))
					end
				end
			end
		end
	end)

	it("has a strip of light in the corridor floor", function()
		assert.are.equal(corridors.LAMP, corridors.kind_at(17, 0, 0, 1))
		assert.are.equal(corridors.FLOOR, corridors.kind_at(17, 0, 1, 1))
		assert.are.equal(corridors.AIR, corridors.kind_at(17, 1, 1, 1))
		assert.are.equal(corridors.GLASS, corridors.kind_at(17, 1, 2, 1))
		assert.are.equal(corridors.GLASS, corridors.kind_at(17, 4, 0, 1))
	end)

	it("is the same in all four directions", function()
		local count = 32
		for a = 16, 45 do
			for l = -9, 9 do
				for y = 0, 6 do
					local function plain(kind)
						return kind
					end
					local east = plain(corridors.kind_at(a, y, l, count))
					assert.are.equal(east, plain(corridors.kind_at(-l, y, a, count)))
					assert.are.equal(east, plain(corridors.kind_at(-a, y, -l, count)))
					assert.are.equal(east, plain(corridors.kind_at(l, y, -a, count)))
				end
			end
		end
	end)

	for _, count in ipairs({ 0, 1, 5, 9, 30 }) do
		it("is closed with " .. count .. " rooms", function()
			local seen = {}
			local queue = { { 0, 1, 0 } }
			local head = 1
			local neighbours = {
				{ 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 },
			}
			while queue[head] do
				local x, y, z = queue[head][1], queue[head][2], queue[head][3]
				head = head + 1
				local id = x .. "," .. y .. "," .. z
				if not seen[id] then
					seen[id] = true
					local kind = kind_at(x, y, z, count)
					assert.is_not_nil(kind, "air leaks out at " .. id)
					if is_open(kind) then
						for _, n in ipairs(neighbours) do
							queue[#queue + 1] = { x + n[1], y + n[2], z + n[3] }
						end
					end
				end
			end
			-- Every room can be reached from the hall.
			for slot = 0, count - 1 do
				local room = corridors.room(slot)
				local p = room.interior_min
				assert.is_true(seen[p.x .. "," .. p.y .. "," .. p.z], "room " .. slot)
			end
		end)
	end

	it("stays within its bounds", function()
		local count = 30
		for direction = 1, 4 do
			local min, max = corridors.bounds(direction, count)
			for x = min.x - 1, max.x + 1 do
				for z = min.z - 1, max.z + 1 do
					for y = -1, max.y + 1 do
						local inside = x >= min.x and x <= max.x and y >= min.y
							and y <= max.y and z >= min.z and z <= max.z
						if not inside and math.abs(x) > 16 and math.abs(z) > 16 then
							assert.is_nil(corridors.kind_at(x, y, z, count))
						end
					end
				end
			end
		end
	end)
end)

describe("lep_lobby corridors rooms", function()
	local count = 30

	it("gives every room a free inside of the right size", function()
		for slot = 0, count - 1 do
			local room = corridors.room(slot)
			local min, max = room.interior_min, room.interior_max
			assert.are.equal(corridors.ROOM_SIZE, max.x - min.x + 1)
			assert.are.equal(corridors.ROOM_SIZE, max.z - min.z + 1)
			assert.are.equal(corridors.ROOM_HEIGHT, max.y - min.y + 1)
			for x = min.x, max.x do
				for z = min.z, max.z do
					for y = min.y, max.y do
						assert.are.equal(corridors.AIR, corridors.kind_at(x, y, z, count))
					end
					local below = corridors.kind_at(x, 0, z, count)
					assert.is_true(below == corridors.FLOOR or below == corridors.LAMP)
					local above = corridors.kind_at(x, max.y + 1, z, count)
					assert.is_true(above == corridors.WALL or above == corridors.LAMP)
				end
			end
		end
	end)

	it("never lets two rooms overlap", function()
		local taken = {}
		for slot = 0, count - 1 do
			local room = corridors.room(slot)
			for x = room.interior_min.x, room.interior_max.x do
				for z = room.interior_min.z, room.interior_max.z do
					local id = x .. "," .. z
					assert.is_nil(taken[id])
					taken[id] = slot
				end
			end
		end
	end)

	it("has a door, a sign above it and a place to stand in front", function()
		for slot = 0, count - 1 do
			local room = corridors.room(slot)
			local e = room.entrance
			assert.are.equal(corridors.AIR, corridors.kind_at(e.x, e.y, e.z, count))
			assert.are.equal(corridors.AIR, corridors.kind_at(e.x, e.y + 1, e.z, count))
			-- Two steps from the entrance towards the room is the doorway.
			local dx, dz = room.look_dir.x * 2, room.look_dir.z * 2
			assert.are.same({ corridors.DOOR, slot },
				{ corridors.kind_at(e.x + dx, 1, e.z + dz, count) })
			assert.are.same({ corridors.DOOR_TOP, slot },
				{ corridors.kind_at(e.x + dx, 2, e.z + dz, count) })
			assert.are.equal(corridors.WALL, corridors.kind_at(e.x + dx, 3, e.z + dz, count))
			assert.are.same({ x = e.x + dx, y = 1, z = e.z + dz }, room.door)

			local s = room.sign
			local kind, sign_slot = corridors.kind_at(s.x, s.y, s.z, count)
			assert.are.equal(corridors.SIGN, kind)
			assert.are.equal(slot, sign_slot)
			local w = room.sign_wall
			assert.are.equal(corridors.WALL,
				corridors.kind_at(s.x + w.x, s.y, s.z + w.z, count))
		end
	end)

	it("has solid walls all around, with the door as the only way in", function()
		for slot = 0, count - 1 do
			local room = corridors.room(slot)
			local min, max = room.interior_min, room.interior_max
			local doors = 0
			for x = min.x - 1, max.x + 1 do
				for z = min.z - 1, max.z + 1 do
					local border = x < min.x or x > max.x or z < min.z or z > max.z
					if border then
						for y = 1, corridors.ROOM_HEIGHT do
							local kind = corridors.kind_at(x, y, z, count)
							if kind == corridors.DOOR or kind == corridors.DOOR_TOP then
								doors = doors + 1
							else
								assert.are.equal(corridors.WALL, kind)
							end
						end
					end
				end
			end
			assert.are.equal(2, doors)
		end
	end)

	it("splits names on the sign at the first underscore", function()
		assert.are.equal("lustiger\nloewe", corridors.sign_text("lustiger_loewe"))
		assert.are.equal("anna", corridors.sign_text("anna"))
		assert.are.equal("a\nb_c", corridors.sign_text("a_b_c"))
		assert.are.equal("", corridors.sign_text(nil))
	end)

	it("knows who is inside a room", function()
		local room = corridors.room(3)
		local p = room.interior_min
		assert.is_true(corridors.is_in_room(3, p.x, p.y, p.z))
		assert.is_false(corridors.is_in_room(4, p.x, p.y, p.z))
		assert.is_false(corridors.is_in_room(3, room.entrance.x, room.entrance.y, room.entrance.z))
		assert.is_false(corridors.is_in_room(3, room.door.x, room.door.y, room.door.z))
	end)

	it("lets owner and staff open and close the door", function()
		for _, door_open in ipairs({ true, false }) do
			assert.is_true(corridors.may_use_door(true, false, false, door_open))
			assert.is_true(corridors.may_use_door(false, true, false, door_open))
		end
	end)

	it("lets visitors only open a closed door from inside", function()
		assert.is_true(corridors.may_use_door(false, false, true, false))
		assert.is_false(corridors.may_use_door(false, false, true, true))
		assert.is_false(corridors.may_use_door(false, false, false, false))
		assert.is_false(corridors.may_use_door(false, false, false, true))
	end)

	it("has no sign for rooms that do not exist", function()
		local s = corridors.room(5).sign
		assert.are.equal(corridors.AIR, corridors.kind_at(s.x, s.y, s.z, 5))
		assert.are.equal(corridors.SIGN, (corridors.kind_at(s.x, s.y, s.z, 6)))
	end)

	it("puts portal and chest spots inside the room", function()
		for slot = 0, count - 1 do
			local room = corridors.room(slot)
			for _, spot in ipairs({ room.portal, room.chest }) do
				assert.is_true(spot.x >= room.interior_min.x and spot.x <= room.interior_max.x)
				assert.is_true(spot.z >= room.interior_min.z and spot.z <= room.interior_max.z)
				assert.are.equal(1, spot.y)
			end
			assert.are.not_same(room.portal, room.chest)
		end
	end)

	it("lists where the four corridors start", function()
		local starts = corridors.starts()
		assert.are.equal(4, #starts)
		for _, entry in ipairs(starts) do
			local s = entry.start
			assert.are.equal(corridors.AIR, corridors.kind_at(s.x, s.y, s.z, 0))
			assert.are.equal(corridors.AIR,
				corridors.kind_at(s.x - entry.dir.x, s.y, s.z - entry.dir.z, 0))
		end
	end)
end)

describe("lep_lobby corridors book", function()
	it("assigns slots in order and remembers them", function()
		local book = corridors.new_book()
		assert.are.same({ 0, true }, { book:assign("anna") })
		assert.are.same({ 1, true }, { book:assign("ben") })
		assert.are.same({ 0, false }, { book:assign("anna") })
		assert.are.equal(2, book:count())
		assert.are.equal("ben", book:owner(1))
		assert.are.equal(1, book:get("ben"))
		assert.is_nil(book:get("carl"))
	end)

	it("survives export and import", function()
		local book = corridors.new_book()
		book:assign("anna")
		book:assign("ben")
		local restored = corridors.new_book(book:export())
		assert.are.equal(2, restored:count())
		assert.are.equal(1, restored:get("ben"))
		assert.are.same({ 2, true }, { restored:assign("carl") })
	end)

	it("ignores broken data", function()
		local book = corridors.new_book({ owners = { anna = 0, ben = 0, carl = -1, dora = "x" } })
		assert.are.equal(1, book:count())
		assert.are.equal(0, corridors.new_book("nonsense"):count())
	end)
end)
