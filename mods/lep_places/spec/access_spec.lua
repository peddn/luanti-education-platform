local access = dofile("mods/lep_places/src/access.lua")

describe("lep_places access rules", function()
	it("allows everything without rules", function()
		assert.is_true(access.new():check("anna", "a", "b"))
	end)

	it("passes player and places to the rules", function()
		local rules = access.new()
		local seen
		rules:register(function(player, from, to)
			seen = { player, from, to }
		end)
		assert.is_true(rules:check("anna", "lobby", "wild"))
		assert.are.same({ "anna", "lobby", "wild" }, seen)
	end)

	it("refuses with the message of the first rule that says no", function()
		local rules = access.new()
		rules:register(function() return true end)
		rules:register(function(_, _, to)
			if to == "wild" then
				return false, "closed"
			end
		end)
		rules:register(function() return false, "never asked" end)
		local ok, message = rules:check("anna", "lobby", "wild")
		assert.is_false(ok)
		assert.are.equal("closed", message)
		ok, message = rules:check("anna", "wild", "lobby")
		assert.is_false(ok)
		assert.are.equal("never asked", message)
	end)

	it("lets a move pass if a rule is broken, and reports it", function()
		local errors = 0
		local rules = access.new(function() errors = errors + 1 end)
		rules:register(function() error("boom") end)
		assert.is_true(rules:check("anna", "a", "b"))
		assert.are.equal(1, errors)
	end)

	it("treats only false as a refusal", function()
		local rules = access.new()
		rules:register(function() return nil, "ignored" end)
		assert.is_true(rules:check("anna", "a", "b"))
	end)

	it("accepts functions only", function()
		assert.has_error(function() access.new():register("no function") end)
	end)
end)
