local forgetting = dofile("mods/lep_core/src/forgetting.lua")

describe("lep_core forgetting", function()
	it("asks every mod, also after one has failed", function()
		local called, errors = {}, {}
		local list = forgetting.new(function(account, err)
			errors[#errors + 1] = account .. ":" .. tostring(err):match("broken")
		end)
		list:register(function(account) called[#called + 1] = "a:" .. account end)
		list:register(function() error("broken") end)
		list:register(function(account) called[#called + 1] = "c:" .. account end)

		assert.equal(1, list:run("anna"))
		assert.same({ "a:anna", "c:anna" }, called)
		assert.same({ "anna:broken" }, errors)
	end)

	it("reports no failure when nothing is registered", function()
		assert.equal(0, forgetting.new():run("anna"))
	end)

	it("takes only functions", function()
		assert.has_error(function() forgetting.new():register("nothing") end)
	end)
end)
