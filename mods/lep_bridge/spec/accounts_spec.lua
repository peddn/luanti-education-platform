local accounts = dofile("mods/lep_bridge/src/accounts.lua")

describe("lep_bridge accounts", function()
	it("reads the order of the backend", function()
		local list = accounts.parse({ accounts = {
			{ name = "klugeEule", password = "wolke-apfel-47" },
			"nonsense",
			{ name = "frohesReh", password = "berg-see-03" },
		} })
		assert.are.same({
			{ name = "klugeEule", password = "wolke-apfel-47" },
			{ name = "frohesReh", password = "berg-see-03" },
		}, list)
		assert.is_nil(accounts.parse(nil))
		assert.is_nil(accounts.parse({}))
		assert.is_nil(accounts.parse({ accounts = "x" }))
		assert.are.same({}, accounts.parse({ accounts = {} }))
	end)

	it("reads the order for a new password", function()
		local name, password = accounts.parse_password(
			{ name = "klugeEule", password = "wolke-apfel-47" })
		assert.are.equal("klugeEule", name)
		assert.are.equal("wolke-apfel-47", password)
		assert.is_nil(accounts.parse_password(nil))
		assert.is_nil(accounts.parse_password({ name = "klugeEule" }))
		assert.is_nil(accounts.parse_password({ name = 5, password = "x" }))
		assert.is_nil(accounts.parse_password({ name = "", password = "x" }))
	end)

	it("runs jobs one after the other", function()
		local log, waiting = {}, {}
		local function defer(next_step)
			waiting[#waiting + 1] = next_step
		end
		local held
		local jobs = {
			function(done) log[#log + 1] = "first" done() end,
			-- This one finishes later, and reports twice.
			function(done) log[#log + 1] = "second" held = done end,
			function(done) log[#log + 1] = "third" done() end,
		}
		accounts.run_in_order(jobs, defer, function() log[#log + 1] = "end" end)
		assert.are.same({ "first" }, log)

		-- Nothing goes on before the pause is over.
		table.remove(waiting, 1)()
		assert.are.same({ "first", "second" }, log)
		assert.are.equal(0, #waiting)

		held()
		held()
		assert.are.equal(1, #waiting)
		table.remove(waiting, 1)()
		assert.are.same({ "first", "second", "third" }, log)
		table.remove(waiting, 1)()
		assert.are.same({ "first", "second", "third", "end" }, log)
	end)

	it("ends at once without jobs", function()
		local ended = false
		accounts.run_in_order({}, function() error("no pause needed") end,
			function() ended = true end)
		assert.is_true(ended)
	end)
end)
