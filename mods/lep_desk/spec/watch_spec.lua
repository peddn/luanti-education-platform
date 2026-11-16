local watch = dofile("mods/lep_desk/src/watch.lua")

local HALL = { place = "lobby", pos = { x = 1, y = 2, z = 3 } }
local ROOM = { place = "room:math", pos = { x = 0, y = 9000, z = 1 } }

describe("lep_desk watch", function()
	it("notes the first jump with its origin", function()
		local list = watch.new()
		assert.is_false(list:is_watching("teacher"))
		assert.is_true(list:start("teacher", HALL, "anna"))
		assert.is_true(list:is_watching("teacher"))
		assert.are.equal("anna", list:get_target("teacher"))
		assert.is_nil(list:get_target("other"))
	end)

	it("keeps the first origin when jumping on", function()
		local list = watch.new()
		list:start("teacher", HALL, "anna")
		assert.is_false(list:start("teacher", ROOM, "ben"))
		assert.are.equal("ben", list:get_target("teacher"))
		assert.are.same(HALL, list:stop("teacher"))
	end)

	it("gives the origin back once", function()
		local list = watch.new()
		list:start("teacher", HALL, "anna")
		assert.are.same(HALL, list:stop("teacher"))
		assert.is_false(list:is_watching("teacher"))
		assert.is_nil(list:stop("teacher"))
	end)

	it("does not keep the tables it was given", function()
		local list = watch.new()
		local origin = { place = "lobby", pos = { x = 1, y = 2, z = 3 } }
		list:start("teacher", origin, "anna")
		origin.pos.x = 99
		assert.are.equal(1, list:stop("teacher").pos.x)
	end)

	it("rejects an origin or a target that is none", function()
		local list = watch.new()
		assert.has_error(function() list:start("teacher", { place = "lobby" }, "anna") end)
		assert.has_error(function() list:start("teacher", HALL, "") end)
		assert.has_error(function() list:start("teacher", HALL, nil) end)
	end)

	it("survives saving and loading", function()
		local list = watch.new()
		list:start("teacher", HALL, "anna")
		local copy = watch.new(list:data())
		assert.are.equal("anna", copy:get_target("teacher"))
		assert.are.same(HALL, copy:stop("teacher"))
	end)

	it("drops stored entries it cannot read", function()
		local list = watch.new({
			good = { origin = HALL, target = "anna" },
			no_target = { origin = HALL },
			no_origin = { target = "anna" },
			broken = "text",
			[5] = { origin = HALL, target = "anna" },
		})
		assert.is_true(list:is_watching("good"))
		assert.is_false(list:is_watching("no_target"))
		assert.is_false(list:is_watching("no_origin"))
		assert.are.same({}, watch.new("broken"):data())
	end)
end)
