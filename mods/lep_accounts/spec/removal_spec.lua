local removal = dofile("mods/lep_accounts/src/removal.lua")

describe("lep_accounts removal", function()
	it("knows an account nobody ever logged in with", function()
		assert.is_false(removal.was_used(-1))
		assert.is_false(removal.was_used(0))
		assert.is_false(removal.was_used(nil))
		assert.is_true(removal.was_used(1763500000))
	end)

	it("removes an ordinary account", function()
		assert.is_true(removal.may_remove(true, true, true, false))
		assert.is_true(removal.may_remove(true, true, false, true))
	end)

	it("refuses an account that does not exist", function()
		assert.same({ false, removal.UNKNOWN }, { removal.may_remove(false, true, false, false) })
	end)

	it("refuses teachers and admins, whoever asks", function()
		assert.same({ false, removal.STAFF }, { removal.may_remove(true, false, false, false) })
		assert.same({ false, removal.STAFF }, { removal.may_remove(true, false, true, true) })
	end)

	it("lets a teacher only take back an account nobody used", function()
		assert.same({ false, removal.USED }, { removal.may_remove(true, true, true, true) })
	end)
end)
