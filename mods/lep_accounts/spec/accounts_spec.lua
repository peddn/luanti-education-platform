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
		-- Accounts that came with an entry have it as their password here.
		has_entry = function(name, entry)
			return existing[name] == entry
		end,
	}
end

local ENTRY = "#1#c2FsdDE#dmVyaWZpZXIx"

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

	it("knows what the engine stores of a password", function()
		assert.is_true(accounts.is_entry(ENTRY))
		assert.is_true(accounts.is_entry("#1#c2FsdA==#dmVy+/ZpZXI="))
		for _, wrong in ipairs({ "", "#1#", "#1##abc", "#1#abc#", "#1#abc", "#2#abc#def",
				"abc#def", "#1#abc#def#ghi", "#1#a b#def", "#1#abc#de\nf", "#1#abc===#def",
				"wolke-apfel-47", "#1#abc#" .. string.rep("a", 600) }) do
			assert.is_false(accounts.is_entry(wrong), wrong)
		end
		assert.is_false(accounts.is_entry(nil))
		assert.is_false(accounts.is_entry(5))
	end)

	it("creates a teacher with the password of another world", function()
		local world = world_with({ lehrer1 = ENTRY, lehrer3 = "another" })
		local to_create, created, refused = accounts.plan({
			{ name = "lehrer1", entry = ENTRY },
			{ name = "lehrer2", entry = ENTRY },
			{ name = "lehrer3", entry = ENTRY },
			-- Not both, and nothing that is no entry.
			{ name = "lehrer4", entry = ENTRY, password = "wolke-apfel-47" },
			{ name = "lehrer5", entry = "wolke-apfel-47" },
			{ name = "lehrer6", password = "wolke-apfel-47" },
		}, world, true)
		assert.are.same({ { name = "lehrer2", entry = ENTRY },
			{ name = "lehrer6", password = "wolke-apfel-47" } }, to_create)
		assert.are.same({ "lehrer1" }, created)
		assert.are.same({ "lehrer3", "lehrer4", "lehrer5" }, refused)

		-- Never for students.
		to_create, created, refused = accounts.plan({ { name = "klugeEule", entry = ENTRY } },
			world_with({}))
		assert.are.same({}, to_create)
		assert.are.same({}, created)
		assert.are.same({ "klugeEule" }, refused)
	end)

	it("takes a managed password only for accounts it created as teachers", function()
		local teacher = { interact = true, shout = true, lep_web_access = true }
		local school = { interact = true, lep_web_access = true, lep_manage_school = true }
		assert.is_true(accounts.may_set_entry("lehrer1", ENTRY, true, true, teacher, "tester"))
		-- The school administration has one password everywhere too.
		assert.is_true(accounts.may_set_entry("leitung", ENTRY, true, true, school, "tester"))
		-- Whatever its privileges are now: the world created it that way.
		assert.is_true(accounts.may_set_entry("lehrer1", ENTRY, true, true, {}, "tester"))

		-- Not for accounts the admin made by hand, whatever they hold,
		-- and not for students.
		for _, held in ipairs({ teacher, school, { interact = true, shout = true } }) do
			assert.same({ false, accounts.UNMANAGED }, { accounts.may_set_entry("lehrer1", ENTRY,
				true, false, held, "tester") })
		end

		-- Never for the admin and for whoever could make themselves one,
		-- even if the account was created on order once.
		assert.same({ false, accounts.STAFF }, { accounts.may_set_entry("tester", ENTRY,
			true, true, teacher, "tester") })
		for _, privilege in ipairs({ "privs", "server" }) do
			local held = { lep_web_access = true, [privilege] = true }
			assert.same({ false, accounts.STAFF }, { accounts.may_set_entry("lehrer1", ENTRY,
				true, true, held, "tester") })
			assert.is_true(accounts.is_locked("lehrer1", held, "tester"))
		end
		assert.is_false(accounts.is_locked("leitung", school, "tester"))
		assert.is_true(accounts.is_locked("tester", {}, "tester"))

		assert.same({ false, accounts.UNKNOWN }, { accounts.may_set_entry("lehrer1", ENTRY,
			false, false, {}, "tester") })
		assert.same({ false, accounts.INVALID }, { accounts.may_set_entry("lehrer1",
			"wolke-apfel-47", true, true, teacher, "tester") })
		assert.same({ false, accounts.INVALID }, { accounts.may_set_entry("lehrer 1", ENTRY,
			true, true, teacher, "tester") })
	end)

	it("lets only unmanaged accounts change their password in the game", function()
		assert.is_true(accounts.may_change_in_game(false))
		assert.is_true(accounts.may_change_in_game(nil))
		assert.is_false(accounts.may_change_in_game(true))
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

	it("lets in only names with an account", function()
		assert.is_true(accounts.may_join(true))
		assert.is_false(accounts.may_join(false))
		-- Nothing but a plain yes opens the door.
		assert.is_false(accounts.may_join(nil))
		assert.is_false(accounts.may_join("tester"))
	end)
	it("sets the password of a teacher only when the order says so", function()
		local ordinary = { interact = true, shout = true }
		local teacher = { interact = true, shout = true, lep_view_players = true,
			lep_web_access = true }
		assert.is_true(accounts.may_set_password("lehrer1", "wolke-apfel-47", true, teacher,
			ordinary, true, "tester"))
		assert.same({ false, accounts.STAFF }, { accounts.may_set_password("lehrer1",
			"wolke-apfel-47", true, teacher, ordinary, false, "tester") })
	end)

	it("never touches the admin and the school administration from outside", function()
		local ordinary = { interact = true, shout = true }
		-- The admin from the settings, even without any privilege.
		assert.is_true(accounts.is_protected("tester", {}, "tester"))
		assert.is_false(accounts.is_protected("lehrer1", { lep_web_access = true }, "tester"))
		for _, privilege in ipairs({ "lep_manage_school", "privs", "server" }) do
			local held = { interact = true, [privilege] = true }
			assert.is_true(accounts.is_protected("leitung", held, "tester"), privilege)
			assert.same({ false, accounts.STAFF }, { accounts.may_set_password("leitung",
				"wolke-apfel-47", true, held, ordinary, true, "tester") })
		end
		assert.is_false(accounts.may_touch(true, true, true))
		assert.is_true(accounts.may_touch(true, false, false))
		assert.is_false(accounts.may_touch(false, false, false))
		assert.is_true(accounts.may_touch(false, true, false))
	end)

	it("knows the privileges of the bundle for teachers", function()
		local set = {}
		for _, privilege in ipairs(accounts.TEACHER_PRIVILEGES) do
			set[privilege] = true
		end
		assert.is_true(set.lep_view_players and set.lep_web_access)
		-- Never what makes somebody the school administration or an admin.
		assert.is_nil(set.lep_manage_school)
		assert.is_nil(set.privs)
		assert.is_nil(set.protection_bypass)
		assert.equal(9, #accounts.TEACHER_PRIVILEGES)
	end)
end)
