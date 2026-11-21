local admin = dofile("mods/lep_accounts/src/admin.lua")

describe("the account of the admin", function()
	it("has an alphabet of 32 characters that are not mistaken for each other", function()
		assert.equal(32, #admin.ALPHABET)
		for _, confusing in ipairs({ "l", "o", "0", "1" }) do
			assert.is_nil(admin.ALPHABET:find(confusing, 1, true))
		end
		local seen = {}
		for character in admin.ALPHABET:gmatch(".") do
			assert.is_nil(seen[character])
			seen[character] = true
		end
	end)

	it("makes a start password from random bytes", function()
		local bytes = string.rep(string.char(0), 20)
		assert.equal("aaaa-aaaa-aaaa-aaaa-aaaa", admin.password_from(bytes))
		-- Every byte picks one character, the same for the same byte.
		local counting = ""
		for value = 0, 19 do
			counting = counting .. string.char(value)
		end
		assert.equal("abcd-efgh-ijkm-npqr-stuv", admin.password_from(counting))
		-- 255 is the last of the alphabet, like 31.
		assert.equal("9999-9999-9999-9999-9999",
			admin.password_from(string.rep(string.char(255), 20)))
		assert.equal(admin.password_from(string.rep(string.char(31), 20)),
			admin.password_from(string.rep(string.char(255), 20)))
	end)

	it("makes no password from too few bytes", function()
		assert.equal(20, admin.bytes_needed())
		assert.is_nil(admin.password_from(string.rep("x", 19)))
		assert.is_nil(admin.password_from(""))
		assert.is_nil(admin.password_from(nil))
		-- More than needed is fine.
		assert.equal(24, #admin.password_from(string.rep("x", 40)))
	end)

	it("creates the account in a new world", function()
		assert.equal(admin.CREATE, admin.decide("tester", false, nil, false))
		-- Even if an old note lies around: without an account it is worth
		-- nothing.
		assert.equal(admin.CREATE, admin.decide("tester", false, "abcd", false))
	end)

	it("leaves an account alone that is there", function()
		-- No note: the account was there before, or the note is gone.
		assert.equal(admin.NOTHING, admin.decide("tester", true, nil, false))
		-- The start password is still in use.
		assert.equal(admin.NOTHING, admin.decide("tester", true, "abcd", true))
	end)

	it("forgets the start password once the admin has another", function()
		assert.equal(admin.FORGET, admin.decide("tester", true, "abcd", false))
	end)

	it("does nothing in a world without an admin", function()
		assert.equal(admin.NOTHING, admin.decide(nil, false, nil, false))
		assert.equal(admin.NOTHING, admin.decide("", false, "abcd", false))
		assert.is_false(admin.is_set(""))
		assert.is_true(admin.is_set("tester"))
	end)
end)
