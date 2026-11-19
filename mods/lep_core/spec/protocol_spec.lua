local protocol = dofile("mods/lep_core/src/protocol.lua")

local COLUMNS = { "account", "text" }

describe("lep_core protocol", function()
	it("writes one line per entry", function()
		local line = protocol.encode("2026-11-16T10:00:00Z", COLUMNS,
			{ account = "lustiger_loewe", text = "hello" })
		assert.are.equal("2026-11-16T10:00:00Z\tlustiger_loewe\thello", line)
	end)

	it("reads an entry back", function()
		local record = { account = "anna", text = "one\ttwo\nthree \\ four" }
		local line = protocol.encode("t", COLUMNS, record)
		assert.is_nil(line:find("\n", 1, true))
		assert.are.equal(2, select(2, line:gsub("\t", "")))
		assert.are.same({ time = "t", account = "anna", text = record.text },
			protocol.decode(COLUMNS, line))
	end)

	it("keeps text that looks like an escape", function()
		for _, text in ipairs({ "\\t", "\\n", "\\\\", "a\\", "\\", "C:\\temp\\new" }) do
			local line = protocol.encode("t", COLUMNS, { account = "a", text = text })
			assert.are.equal(text, protocol.decode(COLUMNS, line).text)
		end
	end)

	it("writes missing values as empty and numbers as text", function()
		local line = protocol.encode("t", { "account", "count", "note" },
			{ account = "anna", count = 3 })
		assert.are.same({ time = "t", account = "anna", count = "3", note = "" },
			protocol.decode({ "account", "count", "note" }, line))
	end)

	it("drops carriage returns", function()
		local line = protocol.encode("t", COLUMNS, { account = "a", text = "x\r\ny" })
		assert.are.equal("x\ny", protocol.decode(COLUMNS, line).text)
	end)

	it("copes with lines that have too few or too many columns", function()
		assert.are.same({ time = "t", account = "anna", text = "" },
			protocol.decode(COLUMNS, "t\tanna"))
		assert.are.same({ time = "t", account = "anna", text = "x" },
			protocol.decode(COLUMNS, "t\tanna\tx\textra"))
		assert.is_nil(protocol.decode(COLUMNS, ""))
		assert.is_nil(protocol.decode(COLUMNS, nil))
	end)

	it("accepts only simple names", function()
		assert.is_true(protocol.is_valid_name("rewards"))
		assert.is_true(protocol.is_valid_name("sign_texts2"))
		for _, name in ipairs({ "", "Rewards", "../x", "a b", "1a", "a.b" }) do
			assert.is_false(protocol.is_valid_name(name))
		end
		assert.is_false(protocol.is_valid_name(nil))
	end)

	it("checks column names", function()
		protocol.check_columns({ "account", "text" })
		assert.has_error(function() protocol.check_columns({}) end)
		assert.has_error(function() protocol.check_columns({ "time" }) end)
		assert.has_error(function() protocol.check_columns({ "a", "a" }) end)
		assert.has_error(function() protocol.check_columns({ "A" }) end)
	end)

	it("returns the last entries, oldest first", function()
		local list = { 1, 2, 3, 4, 5 }
		assert.are.same({ 4, 5 }, protocol.tail(list, 2))
		assert.are.same(list, protocol.tail(list, 9))
		assert.are.same(list, protocol.tail(list, nil))
		assert.are.same({}, protocol.tail({}, 3))
	end)

	describe("entries of an account", function()
		local columns = { "account", "kind", "recipient", "text" }
		local lines = {
			protocol.encode("t1", columns, { account = "anna", kind = "chat", text = "hi bert" }),
			protocol.encode("t2", columns, { account = "bert", kind = "private",
				recipient = "anna", text = "psst" }),
			protocol.encode("t3", columns, { account = "bert", kind = "chat", text = "anna" }),
			protocol.encode("t4", columns, { account = "anna2", kind = "chat", text = "x" }),
		}

		it("finds the numbers of the named columns", function()
			assert.same({ 1, 3 }, protocol.positions(columns, { "account", "recipient" }))
			assert.same({}, protocol.positions(columns, { "nothing" }))
		end)

		it("drops what the account wrote and what was written to it alone", function()
			local kept, removed = protocol.without_account(lines, "anna",
				protocol.positions(columns, { "account", "recipient" }))
			assert.equal(2, removed)
			assert.same({ lines[3], lines[4] }, kept)
		end)

		it("keeps lines of others that only mention the account", function()
			local kept, removed = protocol.without_account(lines, "anna", { 1 })
			assert.equal(1, removed)
			assert.equal(3, #kept)
		end)

		it("compares the whole name, also when it had to be escaped", function()
			local odd = protocol.encode("t", { "account" }, { account = "a\tb" })
			assert.is_true(protocol.concerns(odd, "a\tb", { 1 }))
			assert.is_false(protocol.concerns(odd, "a", { 1 }))
			assert.is_false(protocol.concerns("", "a", { 1 }))
			-- The time is never taken for a name.
			assert.is_false(protocol.concerns(lines[1], "t1", { 1 }))
		end)
	end)
end)
