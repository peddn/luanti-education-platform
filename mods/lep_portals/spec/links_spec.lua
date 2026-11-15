local links = dofile("mods/lep_portals/src/links.lua")

describe("lep_portals links", function()
	it("connects the fixed pair for everyone", function()
		assert.are.equal(links.TO_WILDERNESS, links.destination(links.LOBBY, nil, "anna", false))
		assert.are.equal(links.TO_HALL, links.destination(links.WILDERNESS, nil, "anna", false))
	end)

	it("takes the owner from the room to the plot and back", function()
		assert.are.equal(links.TO_PLOT, links.destination(links.ROOM, "anna", "anna", true))
		assert.are.equal(links.TO_ROOM, links.destination(links.PLOT, "anna", "anna", true))
	end)

	it("gives a hint in the room while no portal is built", function()
		assert.are.equal(links.HINT_BUILD, links.destination(links.ROOM, "anna", "anna", false))
	end)

	it("does not work for visitors in a room", function()
		assert.are.equal(links.HINT_FOREIGN, links.destination(links.ROOM, "anna", "ben", true))
		assert.are.equal(links.HINT_FOREIGN, links.destination(links.ROOM, "anna", "ben", false))
	end)

	it("sends strangers from a plot portal to the hall", function()
		assert.are.equal(links.TO_HALL, links.destination(links.PLOT, "anna", "ben", true))
	end)

	it("knows nothing about other kinds", function()
		assert.is_nil(links.destination("something", "anna", "anna", true))
	end)
end)

describe("lep_portals plot record", function()
	local BASE = { x = 1, y = 2, z = 3 }
	local ARRIVAL = { x = 1, y = 2, z = 4 }

	it("keeps one portal per player and returns the replaced one", function()
		local plots = links.new_plots()
		assert.is_nil(plots:get("anna"))
		assert.is_nil(plots:set("anna", BASE, "x", ARRIVAL))
		local old = plots:set("anna", { x = 9, y = 9, z = 9 }, "z", ARRIVAL)
		assert.are.same(BASE, old.base)
		assert.are.equal("z", plots:get("anna").axis)
	end)

	it("forgets a portal", function()
		local plots = links.new_plots()
		plots:set("anna", BASE, "x", ARRIVAL)
		assert.are.same(BASE, plots:remove("anna").base)
		assert.is_nil(plots:get("anna"))
		assert.is_nil(plots:remove("anna"))
	end)

	it("survives export and import and ignores broken data", function()
		local plots = links.new_plots()
		plots:set("anna", BASE, "x", ARRIVAL)
		local data = plots:export()
		data.ben = { base = "nonsense", axis = "x", arrival = ARRIVAL }
		data.carl = { base = BASE, axis = "y", arrival = ARRIVAL }
		local restored = links.new_plots(data)
		assert.are.same(BASE, restored:get("anna").base)
		assert.is_nil(restored:get("ben"))
		assert.is_nil(restored:get("carl"))
		assert.is_nil(links.new_plots("nonsense"):get("anna"))
	end)
end)
