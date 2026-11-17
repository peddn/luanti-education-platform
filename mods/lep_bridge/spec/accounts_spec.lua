local accounts = dofile("mods/lep_bridge/src/accounts.lua")

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

describe("lep_bridge accounts", function()
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
end)
