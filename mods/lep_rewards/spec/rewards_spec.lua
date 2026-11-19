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

	it("pays for a level task that counts, as hard as its module is", function()
		assert.are.same({ rewards.TASK, rewards.REASON_TASK, "normal" },
			{ rewards.for_result(result()) })
		assert.are.same({ rewards.TASK, rewards.REASON_TASK, "low" },
			{ rewards.for_result(result({ effort = false })) })
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

	it("pays a daily task by the effort it names, normal without one", function()
		assert.are.same({ rewards.TASK, rewards.REASON_DAILY, "normal" },
			{ rewards.for_result(daily()) })
		assert.are.equal("low", select(3, rewards.for_result(daily({ effort = "low" }))))
		assert.are.equal("high", select(3, rewards.for_result(daily({ effort = "high" }))))
		assert.are.equal("normal", select(3, rewards.for_result(daily({ effort = "unknown" }))))
	end)

	it("pays daily tasks on the own level and above, not below", function()
		assert.is_truthy(rewards.for_result(daily({ level = 5 })))
		assert.is_nil(rewards.for_result(daily({ level = 1 })))
	end)

	it("pays exactly one reward for a completed level, the highest that fits", function()
		assert.are.same({ rewards.LEVEL, rewards.REASON_LEVEL }, { rewards.for_level(false, false) })
		assert.are.same({ rewards.STAGE, rewards.REASON_STAGE }, { rewards.for_level(true, false) })
		assert.are.same({ rewards.MODULE, rewards.REASON_MODULE }, { rewards.for_level(false, true) })
		-- The last level ends the module, whatever else it is.
		assert.are.same({ rewards.MODULE, rewards.REASON_MODULE }, { rewards.for_level(true, true) })
	end)
end)

describe("lep_rewards destination", function()
	it("puts daily rewards into the inventory of a player in survival", function()
		assert.are.equal(rewards.TO_INVENTORY,
			rewards.destination(rewards.REASON_DAILY, true))
	end)

	it("puts daily rewards into the chest without the survival inventory", function()
		assert.are.equal(rewards.TO_CHEST, rewards.destination(rewards.REASON_DAILY, false))
		assert.are.equal(rewards.TO_CHEST, rewards.destination(rewards.REASON_DAILY, nil))
	end)

	it("puts all other rewards into the chest", function()
		for _, reason in ipairs({ rewards.REASON_TASK, rewards.REASON_LEVEL,
				rewards.REASON_STAGE }) do
			assert.are.equal(rewards.TO_CHEST, rewards.destination(reason, true))
		end
		assert.are.equal(rewards.TO_CHEST, rewards.destination(nil, true))
	end)
end)

describe("lep_rewards table", function()
	local known = { ["default:steel_ingot"] = true, ["default:gold_ingot"] = true,
		["default:diamond"] = true, ["default:coal_lump"] = true }
	local function is_item(name)
		return known[name] == true
	end

	it("has a default with one item per occasion", function()
		local default = rewards.default_table()
		assert.are.same(default, rewards.check_table(default, is_item))
		assert.are.equal(3, default.module.count)
		-- A copy: changing it leaves the default alone.
		default.task.count = 50
		assert.are.equal(1, rewards.default_table().task.count)
	end)

	it("multiplies the count by the effort", function()
		local default = rewards.default_table()
		assert.are.same({ { name = "default:steel_ingot", count = 1 } },
			rewards.items(default, rewards.TASK, "low"))
		assert.are.same({ { name = "default:steel_ingot", count = 2 } },
			rewards.items(default, rewards.TASK, "normal"))
		assert.are.same({ { name = "default:diamond", count = 9 } },
			rewards.items(default, rewards.MODULE, "high"))
		-- Without an effort it is paid once.
		assert.are.equal(1, rewards.items(default, rewards.LEVEL)[1].count)
		assert.is_nil(rewards.items(default, "nothing", "low"))
	end)

	it("takes a table only as a whole", function()
		local function with(change)
			local candidate = rewards.default_table()
			change(candidate)
			return rewards.check_table(candidate, is_item)
		end
		assert.are.equal(20, with(function(t) t.daily_limit = 20 end).daily_limit)
		assert.are.equal(0, with(function(t) t.daily_limit = 0 end).daily_limit)
		assert.are.equal("default:coal_lump",
			with(function(t) t.task = { name = "default:coal_lump", count = 99 } end).task.name)

		local bad = {
			{ "task", function(t) t.task.name = "default:nothing" end },
			{ "task", function(t) t.task.name = "steel" end },
			{ "level", function(t) t.level.count = 0 end },
			{ "level", function(t) t.level.count = 100 end },
			{ "stage", function(t) t.stage.count = 1.5 end },
			{ "module", function(t) t.module = nil end },
			{ "daily_limit", function(t) t.daily_limit = 21 end },
			{ "daily_limit", function(t) t.daily_limit = -1 end },
			{ "daily_limit", function(t) t.daily_limit = nil end },
		}
		for index, case in ipairs(bad) do
			local clean, why = with(case[2])
			assert.is_nil(clean, "case " .. index)
			assert.are.equal(case[1], why, "case " .. index)
		end
		assert.are.same({ nil, "table" }, { rewards.check_table("nonsense", is_item) })
	end)

	it("drops what it does not know, so nothing else gets into storage", function()
		local candidate = rewards.default_table()
		candidate.extra = "x"
		candidate.task.extra = "y"
		local clean = rewards.check_table(candidate, is_item)
		assert.is_nil(clean.extra)
		assert.is_nil(clean.task.extra)
	end)

	it("repairs a stored table row by row", function()
		assert.are.same(rewards.default_table(), rewards.normalize_table(nil, is_item))
		local stored = {
			task = { name = "default:coal_lump", count = 4 },
			level = { name = "default:gone", count = 2 },
			stage = { name = "default:diamond", count = 500 },
			daily_limit = 8,
		}
		local repaired = rewards.normalize_table(stored, is_item)
		assert.are.same({ name = "default:coal_lump", count = 4 }, repaired.task)
		assert.are.same(rewards.DEFAULT_TABLE.level, repaired.level)
		assert.are.same(rewards.DEFAULT_TABLE.stage, repaired.stage)
		assert.are.same(rewards.DEFAULT_TABLE.module, repaired.module)
		assert.are.equal(8, repaired.daily_limit)
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
