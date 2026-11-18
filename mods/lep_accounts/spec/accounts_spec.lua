local accounts = dofile("mods/lep_accounts/src/accounts.lua")

-- A world with accounts: name -> password.
local function world_with(existing)
	return {
		find = function(name)
			for known in pairs(existing) do
				if known:lower() == name:lower() then
					return known
				end
			end
			return nil
		end,
		has_password = function(name, password)
			return existing[name] == password
		end,
	}
end

local function names(list)
	local result = {}
	for index, entry in ipairs(list) do
		result[index] = type(entry) == "table" and entry.name or entry
	end
	return result
end

describe("lep_accounts", function()
	it("knows the names the engine takes", function()
		assert.is_true(accounts.is_name("klugeEule"))
		assert.is_true(accounts.is_name("a_b-C9"))
		assert.is_true(accounts.is_name(string.rep("a", 20)))
		assert.is_false(accounts.is_name(string.rep("a", 21)))
		assert.is_false(accounts.is_name(""))
		assert.is_false(accounts.is_name("kluge Eule"))
		assert.is_false(accounts.is_name("klügeEule"))
		assert.is_false(accounts.is_name(nil))
		assert.is_false(accounts.is_name(5))
	end)

	it("creates what is free", function()
		local to_create, created, refused = accounts.plan({
			{ name = "klugeEule", password = "wolke-apfel-47" },
			{ name = "frohesReh", password = "berg-see-03" },
		}, world_with({}))
		assert.are.same({ "klugeEule", "frohesReh" }, names(to_create))
		assert.are.equal("wolke-apfel-47", to_create[1].password)
		assert.are.same({}, created)
		assert.are.same({}, refused)
	end)

	it("never touches an account that is there already", function()
		local world = world_with({ klugeEule = "the-own-password", FrohesReh = "x" })
		local to_create, created, refused = accounts.plan({
			{ name = "klugeEule", password = "wolke-apfel-47" },
			-- Taken in other letter case.
			{ name = "frohesReh", password = "berg-see-03" },
			{ name = "mutigerDachs", password = "tal-zelt-11" },
		}, world)
		assert.are.same({ "mutigerDachs" }, names(to_create))
		assert.are.same({}, created)
		assert.are.same({ "klugeEule", "frohesReh" }, refused)
	end)

	it("recognises its own work when the job arrives again", function()
		local world = world_with({ klugeEule = "wolke-apfel-47" })
		local to_create, created, refused = accounts.plan({
			{ name = "klugeEule", password = "wolke-apfel-47" },
			{ name = "frohesReh", password = "berg-see-03" },
		}, world)
		assert.are.same({ "frohesReh" }, names(to_create))
		assert.are.same({ "klugeEule" }, created)
		assert.are.same({}, refused)
	end)

	it("refuses what is no account", function()
		local to_create, created, refused = accounts.plan({
			{ name = "kluge Eule", password = "wolke-apfel-47" },
			{ name = string.rep("a", 21), password = "wolke-apfel-47" },
			{ name = "frohesReh", password = "" },
			{ name = "mutigerDachs" },
			{ password = "tal-zelt-11" },
			{ name = "flinkerOtter", password = "tal-zelt-11" },
			-- The same name twice in one order.
			{ name = "FlinkerOtter", password = "see-berg-12" },
		}, world_with({}))
		assert.are.same({ "flinkerOtter" }, names(to_create))
		assert.are.same({}, created)
		assert.are.same({ "kluge Eule", string.rep("a", 21), "frohesReh", "mutigerDachs",
			"FlinkerOtter" }, refused)
	end)

	it("reads lists of privileges", function()
		assert.are.same({ interact = true, shout = true }, accounts.privilege_set("interact, shout"))
		assert.are.same({ interact = true }, accounts.privilege_set(" interact "))
		assert.are.same({}, accounts.privilege_set(""))
		assert.are.same({}, accounts.privilege_set(nil))
	end)

	it("tells ordinary accounts from teachers and admins", function()
		local ordinary = { interact = true, shout = true }
		assert.is_true(accounts.is_ordinary({ interact = true, shout = true }, ordinary))
		-- A muted student holds less, not more.
		assert.is_true(accounts.is_ordinary({ interact = true }, ordinary))
		assert.is_true(accounts.is_ordinary({}, ordinary))
		assert.is_true(accounts.is_ordinary({ interact = true, fly = false }, ordinary))
		assert.is_false(accounts.is_ordinary({ interact = true, lep_view_players = true }, ordinary))
		assert.is_false(accounts.is_ordinary({ interact = true, shout = true, server = true },
			ordinary))
		assert.is_false(accounts.is_ordinary({ lep_web_access = true }, ordinary))
	end)

	it("leaves out what a place gave", function()
		local ordinary = { interact = true, shout = true }
		-- A student in a room where flying is allowed.
		local student = accounts.without({ interact = true, shout = true, fly = true },
			{ fly = true })
		assert.are.same({ interact = true, shout = true }, student)
		assert.is_true(accounts.is_ordinary(student, ordinary))
		-- A teacher in the same room stays a teacher.
		local teacher = accounts.without(
			{ interact = true, fly = true, lep_view_players = true }, { fly = true })
		assert.is_false(accounts.is_ordinary(teacher, ordinary))
		assert.are.same({ interact = true }, accounts.without({ interact = true, fly = false }, {}))
	end)

	it("sets a password only for an ordinary account that exists", function()
		local ordinary = { interact = true, shout = true }
		local student = { interact = true, shout = true }
		assert.is_true(accounts.may_set_password("klugeEule", "wolke-apfel-47", true, student,
			ordinary))

		local ok, why = accounts.may_set_password("klugeEule", "wolke-apfel-47", false, {},
			ordinary)
		assert.is_false(ok)
		assert.are.equal(accounts.UNKNOWN, why)

		ok, why = accounts.may_set_password("lehrer1", "wolke-apfel-47", true,
			{ interact = true, lep_view_players = true }, ordinary)
		assert.is_false(ok)
		assert.are.equal(accounts.STAFF, why)

		for _, bad in ipairs({ { "kluge Eule", "x" }, { "klugeEule", "" }, { "klugeEule", nil },
			{ nil, "x" } }) do
			ok, why = accounts.may_set_password(bad[1], bad[2], true, student, ordinary)
			assert.is_false(ok)
			assert.are.equal(accounts.INVALID, why)
		end
	end)

	it("lets in only names with an account, and the admin", function()
		assert.is_true(accounts.may_join("klugeEule", true, "tester"))
		assert.is_false(accounts.may_join("fremder", false, "tester"))
		-- The admin may create their own account by entering.
		assert.is_true(accounts.may_join("tester", false, "tester"))
		assert.is_true(accounts.may_join("tester", true, "tester"))
		assert.is_false(accounts.may_join("Tester", false, "tester"))
		-- Without an admin in the settings nobody new gets in.
		assert.is_false(accounts.may_join("fremder", false, nil))
		assert.is_false(accounts.may_join("", false, ""))
	end)
end)
