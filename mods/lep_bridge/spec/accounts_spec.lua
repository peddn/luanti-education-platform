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
	it("reads orders that are meant for teachers", function()
		local list, by = accounts.parse({ accounts = { { name = "lehrer2", password = "x" } },
			teacher = true, by = "leitung" })
		assert.are.same({ { name = "lehrer2", password = "x" } }, list)
		assert.are.equal("leitung", by)
		-- For students nobody is named.
		list, by = accounts.parse({ accounts = {}, teacher = false })
		assert.are.same({}, list)
		assert.is_nil(by)
		-- Privileges are only handed out for somebody who can be named.
		assert.is_nil(accounts.parse({ accounts = {}, teacher = true }))
		assert.is_nil(accounts.parse({ accounts = {}, teacher = true, by = "nobody here" }))
		assert.is_nil(accounts.parse({ accounts = {}, teacher = "yes", by = "leitung" }))

		local name, password, staff_by = accounts.parse_password({ name = "lehrer2",
			password = "x", staff = true, by = "leitung" })
		assert.are.same({ "lehrer2", "x", "leitung" }, { name, password, staff_by })
		name, password, staff_by = accounts.parse_password({ name = "klugeEule", password = "x" })
		assert.are.same({ "klugeEule", "x" }, { name, password })
		assert.is_nil(staff_by)
		assert.is_nil(accounts.parse_password({ name = "lehrer2", password = "x", staff = true }))
	end)

	it("reads what belongs to one password in all worlds", function()
		local entry = "#1#c2FsdDE#dmVyaWZpZXIx"
		local list, by, version = accounts.parse({ accounts = { { name = "lehrer2",
			entry = entry } }, teacher = true, by = "leitung", version = 3 })
		assert.are.same({ { name = "lehrer2", entry = entry } }, list)
		assert.are.same({ "leitung", 3 }, { by, version })
		-- An entry instead of a password is only taken for teachers, and
		-- students have no versions.
		assert.is_nil(accounts.parse({ accounts = { { name = "klugeEule", entry = entry } } }))
		list, by, version = accounts.parse({ accounts = {}, version = 3 })
		assert.are.same({}, list)
		assert.is_nil(by)
		assert.is_nil(version)

		local name, password, staff_by
		name, password, staff_by, version = accounts.parse_password({ name = "lehrer2",
			password = "x", staff = true, by = "leitung", version = 4 })
		assert.are.same({ "lehrer2", "x", "leitung", 4 }, { name, password, staff_by, version })
		name, password, staff_by, version = accounts.parse_password({ name = "lehrer2",
			password = "x", staff = true, by = "leitung", version = -1 })
		assert.are.same({ "lehrer2", "x", "leitung" }, { name, password, staff_by })
		assert.is_nil(version)

		assert.are.same({ "lehrer2", entry, 2 }, { accounts.parse_entry({ name = "lehrer2",
			entry = entry, version = 2 }) })
		for _, wrong in ipairs({
			{ name = "lehrer2", entry = entry },
			{ name = "lehrer2", entry = entry, version = 1.5 },
			{ name = "lehrer2", entry = entry, version = "2" },
			{ name = "lehrer 2", entry = entry, version = 2 },
			{ name = "lehrer2", entry = "", version = 2 },
			{ entry = entry, version = 2 },
		}) do
			assert.is_nil(accounts.parse_entry(wrong))
		end
		assert.is_nil(accounts.parse_entry(nil))
	end)
end)
