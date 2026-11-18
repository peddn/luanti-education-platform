local orders = dofile("mods/lep_bridge/src/orders.lua")

describe("lep_bridge orders", function()
	local function level(changes)
		local payload = { account = "klugeEule", module = "lep_math:math", level = 3, by = "lehrer1" }
		for key, value in pairs(changes or {}) do
			payload[key] = value
		end
		return payload
	end

	it("reads the order for a level", function()
		assert.are.same(
			{ account = "klugeEule", module = "lep_math:math", level = 3, by = "lehrer1" },
			orders.parse_level(level()))
		-- More than the order needs is left out.
		assert.is_nil(orders.parse_level(level({ extra = "x" })).extra)
	end)

	it("refuses an order for a level that cannot be read", function()
		assert.is_nil(orders.parse_level(nil))
		assert.is_nil(orders.parse_level("x"))
		assert.is_nil(orders.parse_level({}))
		for _, changes in ipairs({
			{ level = 0 }, { level = 1.5 }, { level = "3" }, { level = -1 },
			{ account = "" }, { account = 5 }, { account = "a b" }, { account = "a\tb" },
			{ by = "" }, { by = "lehrer\n1" }, { by = string.rep("a", 61) },
			{ module = "math" }, { module = "lep math:x" }, { module = 7 },
		}) do
			assert.is_nil(orders.parse_level(level(changes)), next(changes))
		end
	end)

	it("reads the order for a lock", function()
		local payload = { account = "klugeEule", module = "lep_math:math", locked = false,
			by = "lehrer1" }
		assert.are.same(payload, orders.parse_locked(payload))
		payload.locked = true
		assert.is_true(orders.parse_locked(payload).locked)
		payload.locked = "yes"
		assert.is_nil(orders.parse_locked(payload))
		payload.locked = nil
		assert.is_nil(orders.parse_locked(payload))
		assert.is_nil(orders.parse_locked({ locked = true }))
	end)

	it("reads the orders about display names", function()
		assert.are.same({ account = "klugeEule", by = "lehrer1" },
			orders.parse_remove_name({ account = "klugeEule", by = "lehrer1", extra = 1 }))
		assert.are.same({ account = "klugeEule", by = "lehrer1", locked = true },
			orders.parse_name_lock({ account = "klugeEule", by = "lehrer1", locked = true }))
		assert.is_false(
			orders.parse_name_lock({ account = "klugeEule", by = "lehrer1", locked = false }).locked)
		for _, payload in ipairs({
			{ account = "klugeEule" }, { by = "lehrer1" }, { account = "kluge Eule", by = "lehrer1" },
			{ account = "klugeEule", by = "lehrer\n1" }, { account = 5, by = "lehrer1" },
		}) do
			assert.is_nil(orders.parse_remove_name(payload))
			payload.locked = true
			assert.is_nil(orders.parse_name_lock(payload))
		end
		assert.is_nil(orders.parse_remove_name(nil))
		assert.is_nil(orders.parse_name_lock({ account = "klugeEule", by = "lehrer1" }))
		assert.is_nil(orders.parse_name_lock({ account = "klugeEule", by = "lehrer1", locked = 1 }))
	end)

	it("describes an order for the protocol", function()
		assert.are.equal("web:set_level lep_math:math 3",
			orders.describe("set_level", orders.parse_level(level())))
		local lock = { account = "a", module = "lep_math:math", locked = true, by = "b" }
		assert.are.equal("web:set_locked lep_math:math on", orders.describe("set_locked", lock))
		lock.locked = false
		assert.are.equal("web:set_locked lep_math:math off", orders.describe("set_locked", lock))
	end)
end)
