local rooms = dofile("mods/lep_rooms/src/rooms.lua")

local TYPE = "test:room"

local function new_types()
	local types = rooms.new_types()
	types:register(TYPE, { layer = 1, size = { x = 20, y = 10, z = 30 } })
	return types
end

describe("lep_rooms slot_to_cell", function()
	it("starts in the centre", function()
		assert.are.same({ 0, 0 }, { rooms.slot_to_cell(0) })
	end)

	it("walks the first ring", function()
		local expected = {
			{ 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 },
			{ -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 },
		}
		for slot, cell in ipairs(expected) do
			assert.are.same(cell, { rooms.slot_to_cell(slot) })
		end
	end)

	it("never uses a cell twice and stays inside the usable area", function()
		local seen = {}
		for slot = 0, rooms.CAPACITY - 1 do
			local i, j = rooms.slot_to_cell(slot)
			local key = i .. "," .. j
			assert.is_nil(seen[key])
			seen[key] = true
			assert.is_true(math.abs(i) <= rooms.MAX_CELL)
			assert.is_true(math.abs(j) <= rooms.MAX_CELL)
		end
	end)

	it("rejects invalid slots", function()
		assert.has_error(function() rooms.slot_to_cell(-1) end)
		assert.has_error(function() rooms.slot_to_cell(1.5) end)
	end)
end)

describe("lep_rooms types", function()
	it("stores a type with defaults", function()
		local def = new_types():get(TYPE)
		assert.are.equal(1, def.layer)
		assert.are.equal(1, def.version)
		assert.are.same({ x = 20, y = 10, z = 30 }, def.size)
		assert.are.same({}, def.privileges)
	end)

	it("finds a type by its layer", function()
		local types = new_types()
		assert.are.equal(TYPE, types:id_on_layer(1))
		assert.is_nil(types:id_on_layer(2))
	end)

	it("lists ids sorted", function()
		local types = new_types()
		types:register("a:room", { layer = 2, size = { x = 3, y = 3, z = 3 } })
		assert.are.same({ "a:room", TYPE }, types:ids())
	end)

	it("rejects duplicate ids and layers", function()
		local types = new_types()
		assert.has_error(function()
			types:register(TYPE, { layer = 2, size = { x = 3, y = 3, z = 3 } })
		end)
		assert.has_error(function()
			types:register("other", { layer = 1, size = { x = 3, y = 3, z = 3 } })
		end)
	end)

	it("rejects invalid definitions", function()
		local types = rooms.new_types()
		local ok_size = { x = 5, y = 5, z = 5 }
		assert.has_error(function() types:register("a", { layer = -1, size = ok_size }) end)
		assert.has_error(function()
			types:register("a", { layer = rooms.MAX_LAYER + 1, size = ok_size })
		end)
		assert.has_error(function() types:register("a", { layer = 1.5, size = ok_size }) end)
		assert.has_error(function() types:register("a", { layer = 1 }) end)
		assert.has_error(function()
			types:register("a", { layer = 1, size = { x = 2, y = 5, z = 5 } })
		end)
		assert.has_error(function()
			types:register("a", { layer = 1, size = { x = 5, y = rooms.MAX_SIZE + 1, z = 5 } })
		end)
		assert.has_error(function()
			types:register("a", { layer = 1, size = ok_size, version = 0 })
		end)
	end)
end)

describe("lep_rooms geometry", function()
	local def = new_types():get(TYPE)

	it("places slot 0 in the centre of the world on its layer", function()
		local g = rooms.geometry(def, 0)
		local floor_y = rooms.BASE_Y + rooms.PITCH
		assert.are.same({ x = -10, y = floor_y + 1, z = -15 }, g.interior_min)
		assert.are.same({ x = 9, y = floor_y + 10, z = 14 }, g.interior_max)
	end)

	it("has the requested interior size", function()
		local g = rooms.geometry(def, 7)
		assert.are.equal(20, g.interior_max.x - g.interior_min.x + 1)
		assert.are.equal(10, g.interior_max.y - g.interior_min.y + 1)
		assert.are.equal(30, g.interior_max.z - g.interior_min.z + 1)
	end)

	it("wraps the interior in a one node thick shell", function()
		local g = rooms.geometry(def, 3)
		for _, axis in ipairs({ "x", "y", "z" }) do
			assert.are.equal(g.interior_min[axis] - 1, g.shell_min[axis])
			assert.are.equal(g.interior_max[axis] + 1, g.shell_max[axis])
		end
	end)

	it("puts the spawn point on the floor at the front wall", function()
		local g = rooms.geometry(def, 0)
		assert.are.same({ x = 0, y = g.interior_min.y, z = g.interior_min.z + 1 }, g.spawn)
	end)

	it("keeps neighbouring rooms one pitch apart", function()
		local a = rooms.geometry(def, 0)
		local b = rooms.geometry(def, 1)
		assert.are.equal(rooms.PITCH, b.spawn.x - a.spawn.x)
		assert.are.equal(a.spawn.z, b.spawn.z)
	end)

	it("keeps layers one pitch apart", function()
		local types = new_types()
		types:register("upper", { layer = 2, size = { x = 20, y = 10, z = 30 } })
		local a = rooms.geometry(types:get(TYPE), 0)
		local b = rooms.geometry(types:get("upper"), 0)
		assert.are.equal(rooms.PITCH, b.spawn.y - a.spawn.y)
	end)

	it("keeps the largest room on the highest layer inside the world", function()
		local types = rooms.new_types()
		types:register("big", {
			layer = rooms.MAX_LAYER,
			size = { x = rooms.MAX_SIZE, y = rooms.MAX_SIZE, z = rooms.MAX_SIZE },
		})
		local g = rooms.geometry(types:get("big"), rooms.CAPACITY - 1)
		for _, axis in ipairs({ "x", "y", "z" }) do
			assert.is_true(math.abs(g.shell_min[axis]) < 30900)
			assert.is_true(math.abs(g.shell_max[axis]) < 30900)
		end
	end)

	it("rejects slots outside the usable area", function()
		assert.has_error(function() rooms.geometry(def, rooms.CAPACITY) end)
	end)
end)

describe("lep_rooms book", function()
	it("assigns slots in order and keeps them", function()
		local book = rooms.new_book()
		assert.are.equal(0, book:assign(TYPE, "anna").slot)
		assert.are.equal(1, book:assign(TYPE, "ben").slot)
		assert.are.equal(0, book:assign(TYPE, "anna").slot)
	end)

	it("counts slots separately per room type", function()
		local book = rooms.new_book()
		book:assign(TYPE, "anna")
		assert.are.equal(0, book:assign("other", "ben").slot)
	end)

	it("returns nil for players without a room", function()
		assert.is_nil(rooms.new_book():get(TYPE, "anna"))
	end)

	it("tracks whether a room needs to be built", function()
		local book = rooms.new_book()
		assert.is_true(book:needs_build(TYPE, "anna", 1))
		book:assign(TYPE, "anna")
		assert.is_true(book:needs_build(TYPE, "anna", 1))
		book:mark_built(TYPE, "anna", 1)
		assert.is_false(book:needs_build(TYPE, "anna", 1))
		assert.is_true(book:needs_build(TYPE, "anna", 2))
	end)

	it("lists owners sorted", function()
		local book = rooms.new_book()
		book:assign(TYPE, "zoe")
		book:assign(TYPE, "anna")
		assert.are.same({ "anna", "zoe" }, book:owners(TYPE))
		assert.are.same({}, book:owners("other"))
	end)

	it("survives export and import", function()
		local book = rooms.new_book()
		book:assign(TYPE, "anna")
		book:assign(TYPE, "ben")
		book:mark_built(TYPE, "ben", 3)

		local restored = rooms.new_book(book:export())

		assert.are.equal(0, restored:get(TYPE, "anna").slot)
		assert.are.equal(1, restored:get(TYPE, "ben").slot)
		assert.are.equal(3, restored:get(TYPE, "ben").built_version)
		assert.are.equal(2, restored:assign(TYPE, "cem").slot)
	end)

	it("never reuses a slot when next_slot is missing in stored data", function()
		local restored = rooms.new_book({
			types = { [TYPE] = { rooms = { anna = { slot = 4 } } } },
		})
		assert.are.equal(5, restored:assign(TYPE, "ben").slot)
	end)

	it("ignores broken stored data", function()
		local restored = rooms.new_book({
			types = {
				[TYPE] = { rooms = { anna = { slot = "x" }, ben = "broken", cem = { slot = 2 } } },
				other = "broken",
			},
		})
		assert.is_nil(restored:get(TYPE, "anna"))
		assert.is_nil(restored:get(TYPE, "ben"))
		assert.are.equal(2, restored:get(TYPE, "cem").slot)
		assert.has_no.errors(function() rooms.new_book("garbage") end)
	end)

	it("reports a full layer instead of reusing rooms", function()
		local restored = rooms.new_book({
			types = { [TYPE] = { next_slot = rooms.CAPACITY, rooms = {} } },
		})
		local record, err = restored:assign(TYPE, "anna")
		assert.is_nil(record)
		assert.is_truthy(err:find("no free room", 1, true))
	end)
end)

describe("lep_rooms locate and may_modify", function()
	local types, book, g_anna, g_ben

	before_each(function()
		types = new_types()
		book = rooms.new_book()
		g_anna = rooms.geometry(types:get(TYPE), book:assign(TYPE, "anna").slot)
		g_ben = rooms.geometry(types:get(TYPE), book:assign(TYPE, "ben").slot)
	end)

	it("returns nil outside all room layers", function()
		assert.is_nil(rooms.locate(types, book, { x = 0, y = 10, z = 0 }))
		assert.is_nil(rooms.locate(types, book, { x = 0, y = rooms.BASE_Y + 5, z = 0 }))
		assert.is_nil(rooms.may_modify(types, book, { x = 0, y = 10, z = 0 }, "anna"))
	end)

	it("recognizes the interior of a room", function()
		local where = rooms.locate(types, book, g_anna.spawn)
		assert.are.equal(TYPE, where.type_id)
		assert.are.equal("anna", where.owner)
		assert.are.equal("interior", where.part)
	end)

	it("recognizes the corners of the interior", function()
		assert.are.equal("interior", rooms.locate(types, book, g_anna.interior_min).part)
		assert.are.equal("interior", rooms.locate(types, book, g_anna.interior_max).part)
	end)

	it("recognizes the shell", function()
		assert.are.equal("shell", rooms.locate(types, book, g_anna.shell_min).part)
		assert.are.equal("shell", rooms.locate(types, book, g_anna.shell_max).part)
		local floor = { x = g_anna.spawn.x, y = g_anna.spawn.y - 1, z = g_anna.spawn.z }
		assert.are.equal("shell", rooms.locate(types, book, floor).part)
	end)

	it("recognizes the space around a room", function()
		local beside = { x = g_anna.shell_max.x + 1, y = g_anna.spawn.y, z = 0 }
		local where = rooms.locate(types, book, beside)
		assert.are.equal("outside", where.part)
		assert.are.equal("anna", where.owner)
	end)

	it("recognizes a free cell", function()
		local far = { x = 10 * rooms.PITCH, y = g_anna.spawn.y, z = 0 }
		local where = rooms.locate(types, book, far)
		assert.are.equal("outside", where.part)
		assert.is_nil(where.owner)
	end)

	it("tells rooms apart", function()
		assert.are.equal("ben", rooms.locate(types, book, g_ben.spawn).owner)
	end)

	it("lets only the owner modify the interior", function()
		assert.is_true(rooms.may_modify(types, book, g_anna.spawn, "anna"))
		assert.is_false(rooms.may_modify(types, book, g_anna.spawn, "ben"))
	end)

	it("lets nobody modify the shell or the space between rooms", function()
		assert.is_false(rooms.may_modify(types, book, g_anna.shell_min, "anna"))
		local beside = { x = g_anna.shell_max.x + 1, y = g_anna.spawn.y, z = 0 }
		assert.is_false(rooms.may_modify(types, book, beside, "anna"))
		local far = { x = 10 * rooms.PITCH, y = g_anna.spawn.y, z = 0 }
		assert.is_false(rooms.may_modify(types, book, far, "anna"))
	end)
end)
