local rewards = dofile("mods/lep_rewards/src/rewards.lua")

local LIMIT = 3

describe("lep_rewards rules", function()
	local function result(overrides)
		local r = {
			solved = true, level = 2, player_level = 2,
			kind = rewards.KIND_TASK, counted = true, effort = "normal",
		}
		for key, value in pairs(overrides or {}) do
			r[key] = value
		end
		return r
	end

	local function daily(overrides)
		local r = result({ kind = rewards.KIND_DAILY, counted = false })
		for key, value in pairs(overrides or {}) do
			r[key] = value
		end
		return r
	end

	it("pays the small reward for a level task that counts", function()
		assert.are.same({ rewards.SMALL, rewards.REASON_TASK }, { rewards.for_result(result()) })
	end)

	it("pays nothing for a level task that no longer counts", function()
		-- The task type is done, or the task is not on the player's level.
		assert.is_nil(rewards.for_result(result({ counted = false })))
		assert.is_nil(rewards.for_result(result({ counted = false, level = 5 })))
	end)

	it("pays nothing for wrong answers", function()
		assert.is_nil(rewards.for_result(result({ solved = false })))
		assert.is_nil(rewards.for_result(daily({ solved = false })))
	end)

	it("pays the medium reward for a daily task", function()
		assert.are.same({ rewards.MEDIUM, rewards.REASON_DAILY }, { rewards.for_result(daily()) })
	end)

	it("sizes the reward of a daily task by its effort", function()
		assert.are.equal(rewards.SMALL, (rewards.for_result(daily({ effort = "low" }))))
		assert.are.equal(rewards.MEDIUM, (rewards.for_result(daily({ effort = "normal" }))))
		assert.are.equal(rewards.LARGE, (rewards.for_result(daily({ effort = "high" }))))
		assert.are.equal(rewards.MEDIUM, (rewards.for_result(daily({ effort = "unknown" }))))
	end)

	it("pays daily tasks on the own level and above, not below", function()
		assert.is_truthy(rewards.for_result(daily({ level = 5 })))
		assert.is_nil(rewards.for_result(daily({ level = 1 })))
	end)

	it("pays the large reward only at the end of a stage", function()
		assert.are.same({ rewards.LARGE, rewards.REASON_STAGE }, { rewards.for_level(true) })
		assert.are.same({ rewards.MEDIUM, rewards.REASON_LEVEL }, { rewards.for_level(false) })
	end)
end)

describe("lep_rewards items", function()
	it("reads a list of items", function()
		assert.are.same({
			{ name = "default:steel_ingot", count = 1 },
			{ name = "default:coal_lump", count = 3 },
			{ name = "farming:bread", count = 1 },
		}, rewards.parse_items("default:steel_ingot 1,default:coal_lump 3 ,  farming:bread"))
	end)

	it("reads the defaults", function()
		for _, size in ipairs(rewards.SIZES) do
			assert.is_truthy(rewards.parse_items(rewards.DEFAULT_ITEMS[size]))
		end
	end)

	it("rejects what it cannot read", function()
		for _, text in ipairs({ "", " , ", "steel 1", "default:steel_ingot x",
				"default:steel_ingot 0", "default:steel_ingot 1 2", "a:b; c:d" }) do
			assert.is_nil(rewards.parse_items(text), text)
		end
		assert.is_nil(rewards.parse_items(nil))
	end)
end)

describe("lep_rewards daily allowance", function()
	it("counts down", function()
		local state = rewards.new_allowance()
		assert.are.equal(3, rewards.remaining(state, "d1", LIMIT))
		local allowed, left
		state, allowed, left = rewards.use_allowance(state, "d1", LIMIT)
		assert.is_true(allowed)
		assert.are.equal(2, left)
		assert.are.equal(2, rewards.remaining(state, "d1", LIMIT))
	end)

	it("stops at the limit", function()
		local state = rewards.new_allowance()
		local allowed, left
		for _ = 1, 3 do
			state, allowed, left = rewards.use_allowance(state, "d1", LIMIT)
		end
		assert.is_true(allowed)
		assert.are.equal(0, left)
		state, allowed = rewards.use_allowance(state, "d1", LIMIT)
		assert.is_false(allowed)
		assert.are.equal(3, state.daily)
	end)

	it("allows nothing with a limit of zero", function()
		local _, allowed = rewards.use_allowance(rewards.new_allowance(), "d1", 0)
		assert.is_false(allowed)
	end)

	it("starts again on a new day", function()
		local state = rewards.new_allowance()
		for _ = 1, 3 do
			state = rewards.use_allowance(state, "d1", LIMIT)
		end
		assert.are.equal(3, rewards.remaining(state, "d2", LIMIT))
		local allowed
		state, allowed = rewards.use_allowance(state, "d2", LIMIT)
		assert.is_true(allowed)
		assert.are.same({ day = "d2", daily = 1 }, state)
	end)

	it("does not change the state it was given", function()
		local state = rewards.new_allowance()
		rewards.use_allowance(state, "d1", LIMIT)
		assert.are.same(rewards.new_allowance(), state)
	end)

	it("repairs stored data", function()
		assert.are.same(rewards.new_allowance(), rewards.normalize_allowance(nil))
		assert.are.same({ day = "d1", daily = 2 },
			rewards.normalize_allowance({ day = "d1", daily = 2.7, task = 9, chest = 4 }))
		assert.are.same({ day = "", daily = 0 },
			rewards.normalize_allowance({ day = 5, daily = "many" }))
	end)
end)
