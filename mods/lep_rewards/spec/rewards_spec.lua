local rewards = dofile("mods/lep_rewards/src/rewards.lua")

local LIMITS = { task = 3, chest = 2 }

describe("lep_rewards rules", function()
	local function result(overrides)
		local r = { solved = true, level = 2, player_level = 2, kind = rewards.KIND_TASK }
		for key, value in pairs(overrides or {}) do
			r[key] = value
		end
		return r
	end

	it("pays the small reward for a solved task on the own level", function()
		assert.are.same({ rewards.SMALL, rewards.REASON_TASK }, { rewards.for_result(result()) })
	end)

	it("pays the medium reward for a task chest", function()
		assert.are.same({ rewards.MEDIUM, rewards.REASON_CHEST },
			{ rewards.for_result(result({ kind = rewards.KIND_CHEST })) })
	end)

	it("also pays for tasks above the own level", function()
		assert.are.equal(rewards.SMALL, (rewards.for_result(result({ level = 5 }))))
	end)

	it("pays nothing for tasks below the own level or wrong answers", function()
		assert.is_nil(rewards.for_result(result({ level = 1 })))
		assert.is_nil(rewards.for_result(result({ solved = false })))
		assert.is_nil(rewards.for_result(result({ level = 1, kind = rewards.KIND_CHEST })))
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
	it("counts down per kind", function()
		local state = rewards.new_allowance()
		assert.are.same({ task = 3, chest = 2 }, rewards.remaining(state, "d1", LIMITS))
		local allowed, left
		state, allowed, left = rewards.use_allowance(state, "d1", rewards.KIND_TASK, LIMITS)
		assert.is_true(allowed)
		assert.are.equal(2, left)
		assert.are.same({ task = 2, chest = 2 }, rewards.remaining(state, "d1", LIMITS))
	end)

	it("stops at the limit", function()
		local state = rewards.new_allowance()
		local allowed, left
		for _ = 1, 3 do
			state, allowed, left = rewards.use_allowance(state, "d1", rewards.KIND_TASK, LIMITS)
		end
		assert.is_true(allowed)
		assert.are.equal(0, left)
		state, allowed = rewards.use_allowance(state, "d1", rewards.KIND_TASK, LIMITS)
		assert.is_false(allowed)
		assert.are.equal(3, state.task)
		-- Chests have their own limit.
		local _, chest_allowed = rewards.use_allowance(state, "d1", rewards.KIND_CHEST, LIMITS)
		assert.is_true(chest_allowed)
	end)

	it("starts again on a new day", function()
		local state = rewards.new_allowance()
		for _ = 1, 3 do
			state = rewards.use_allowance(state, "d1", rewards.KIND_TASK, LIMITS)
		end
		assert.are.same({ task = 3, chest = 2 }, rewards.remaining(state, "d2", LIMITS))
		local allowed
		state, allowed = rewards.use_allowance(state, "d2", rewards.KIND_TASK, LIMITS)
		assert.is_true(allowed)
		assert.are.same({ day = "d2", task = 1, chest = 0 }, state)
	end)

	it("does not change the state it was given", function()
		local state = rewards.new_allowance()
		rewards.use_allowance(state, "d1", rewards.KIND_TASK, LIMITS)
		assert.are.same(rewards.new_allowance(), state)
	end)

	it("repairs stored data", function()
		assert.are.same(rewards.new_allowance(), rewards.normalize_allowance(nil))
		assert.are.same({ day = "d1", task = 2, chest = 0 },
			rewards.normalize_allowance({ day = "d1", task = 2.7, chest = -4, other = 1 }))
		assert.are.same({ day = "", task = 0, chest = 0 },
			rewards.normalize_allowance({ day = 5, task = "many" }))
	end)
end)
