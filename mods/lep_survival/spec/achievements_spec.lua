local achievements = dofile("mods/lep_survival/src/achievements.lua")

describe("lep_survival achievements", function()
	it("switches off the achievement for dying a hundred times, and only that", function()
		assert.is_true(achievements.is_disabled("award_you_suck"))
		assert.is_false(achievements.is_disabled("award_lumberjack"))
		assert.is_false(achievements.is_disabled("award_burn"))
		local count = 0
		for _ in pairs(achievements.DISABLED) do
			count = count + 1
		end
		assert.are.equal(1, count)
	end)

	it("builds trophy ids and valid node names", function()
		assert.are.equal("lep_survival:award:award_lumberjack",
			achievements.trophy_id("award_lumberjack"))
		assert.are.equal("lep_survival:plaque_award_lumberjack",
			achievements.node_name("award_lumberjack"))
		local odd = achievements.node_name("My-Mod:Award 1")
		assert.is_truthy(odd:match("^lep_survival:plaque_[a-z0-9_]+$"))
	end)

	it("lists the achievements that become trophies, sorted, without the disabled", function()
		assert.are.same({ "award_a", "award_b" },
			achievements.as_trophies({ award_b = {}, award_you_suck = {}, award_a = {} }))
		assert.are.same({}, achievements.as_trophies({}))
	end)
end)
