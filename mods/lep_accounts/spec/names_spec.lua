local names = dofile("mods/lep_accounts/src/names.lua")

local DAY = 24 * 60 * 60
local function free() return false end

describe("lep_accounts names check", function()
	it("takes letters, umlauts, digits and single separators inside", function()
		for _, name in ipairs({
			"Lena", "Al", "Jörg", "Ägidius", "Weiß", "Anna-Lena", "Ole 2", "Übermut",
			"Max Mustermann", "abcdefghijklmnop", "ÄÖÜäöüßÄÖÜäöüßÄÖ",
		}) do
			assert.are.equal(name, names.check(name))
		end
	end)

	it("cuts off spaces around the name", function()
		assert.are.equal("Lena", names.check("  Lena "))
		assert.are.equal("Anna Lena", names.check("Anna Lena\n"))
	end)

	it("counts characters, not bytes", function()
		assert.are.same({ nil, names.SHORT }, { names.check("ä") })
		assert.are.equal("äö", names.check("äö"))
		assert.are.same({ nil, names.LONG }, { names.check("ÄÖÜäöüßÄÖÜäöüßÄÖÜ") })
	end)

	it("says why a name does not fit", function()
		assert.are.same({ nil, names.SHORT }, { names.check("") })
		assert.are.same({ nil, names.SHORT }, { names.check("  a  ") })
		assert.are.same({ nil, names.LONG }, { names.check("abcdefghijklmnopq") })
		for _, name in ipairs({
			"Le_na", "Lena!", "Léna", "Lena\tMaier", "Anna  Lena", "Anna- Lena", "-Anna", "Anna-",
			"a\nb", "<b>fett", "Lena;", "Łukasz", "😀😀", "a\0b", "\195",
		}) do
			assert.are.same({ nil, names.CHARACTERS }, { names.check(name) }, name)
		end
		assert.are.same({ nil, names.CHARACTERS }, { names.check(nil) })
		assert.are.same({ nil, names.CHARACTERS }, { names.check(42) })
	end)

	it("compares names without the case of their letters", function()
		assert.are.equal(names.fold("LENA"), names.fold("lena"))
		assert.are.equal(names.fold("JÖRG Ä"), names.fold("jörg ä"))
		assert.are.equal("klugeeule", names.fold("klugeEule"))
		assert.are_not.equal(names.fold("Lena"), names.fold("Lenä"))
		assert.are_not.equal(names.fold("Anna Lena"), names.fold("Anna-Lena"))
	end)
end)

describe("lep_accounts names state", function()
	it("lets a player choose a name and remembers when", function()
		local state = names.choose(names.new_state(), "Lena", 1000, free)
		assert.are.same({ display = "Lena", changed_at = 1000, locked = false }, state)
	end)

	it("refuses a name another account has", function()
		local asked
		local state, why = names.choose(names.new_state(), "LENA", 1000, function(folded)
			asked = folded
			return true
		end)
		assert.is_nil(state)
		assert.are.equal(names.TAKEN, why)
		assert.are.equal("lena", asked)
	end)

	it("makes a player wait a period for the next name", function()
		local state = names.choose(names.new_state(), "Lena", 1000, free)
		local again, why, from = names.choose(state, "Lea", 1000 + 29 * DAY, free)
		assert.is_nil(again)
		assert.are.equal(names.WAIT, why)
		assert.are.equal(1000 + 30 * DAY, from)
		assert.are.equal(1000 + 30 * DAY, names.next_change(state, 2000))
		again = names.choose(state, "Lea", 1000 + 30 * DAY, free)
		assert.are.equal("Lea", again.display)
		assert.is_nil(names.next_change(again, 1000 + 61 * DAY))
	end)

	it("lets a player go back to the account name without shortening the wait", function()
		local state = names.choose(names.new_state(), "Lena", 1000, free)
		assert.are.same({ false, names.WAIT, 1000 + 30 * DAY }, { names.may_change(state, 2000) })
		-- Going back works during the wait.
		state = names.give_up(state)
		assert.is_nil(state.display)
		local again, why = names.choose(state, "Lea", 2000, free)
		assert.is_nil(again)
		assert.are.equal(names.WAIT, why)
		-- And it starts no new wait.
		assert.is_true(names.may_change(state, 1000 + 30 * DAY))
		assert.are.equal("Lea", names.choose(state, "Lea", 1000 + 30 * DAY, free).display)
	end)

	it("lets a player choose again right after a teacher removed the name", function()
		local state = names.choose(names.new_state(), "Lena Maier", 1000, free)
		state = names.remove(state)
		assert.is_nil(state.display)
		state = names.choose(state, "Lena", 2000, free)
		assert.are.equal("Lena", state.display)
	end)

	it("locks choosing but keeps the name and lets the player give it up", function()
		local state = names.choose(names.new_state(), "Lena", 1000, free)
		state = names.set_locked(state, true)
		assert.are.equal("Lena", state.display)
		local again, why = names.choose(state, "Lea", 1000 + 40 * DAY, free)
		assert.is_nil(again)
		assert.are.equal(names.LOCKED, why)
		-- Removed and locked: no new name until the lock is lifted.
		local removed = names.remove(state)
		assert.is_true(removed.locked)
		assert.are.equal(names.LOCKED, select(2, names.choose(removed, "Lea", 2000, free)))
		assert.are.same({ false, names.LOCKED }, { names.may_change(state, 1000 + 40 * DAY) })
		-- Going back to the account name works under a lock, and the lock stays.
		local back = names.give_up(state)
		assert.is_nil(back.display)
		assert.is_true(back.locked)
		state = names.set_locked(names.remove(state), false)
		assert.are.equal("Lea", names.choose(state, "Lea", 2000, free).display)
	end)

	it("does not change the state it was given", function()
		local state = names.choose(names.new_state(), "Lena", 1000, free)
		names.remove(state)
		names.give_up(state)
		names.set_locked(state, true)
		assert.are.same({ display = "Lena", changed_at = 1000, locked = false }, state)
	end)

	it("repairs a state from storage", function()
		assert.are.same({ locked = false }, names.normalize(nil))
		assert.are.same({ locked = false }, names.normalize("x"))
		assert.are.same({ display = "Lena", changed_at = 5, locked = true },
			names.normalize({ display = "Lena", changed_at = 5, locked = true, extra = 1 }))
		-- A name that does not pass the rules any more is dropped.
		assert.are.same({ locked = false, changed_at = 5 },
			names.normalize({ display = "Le<na", changed_at = 5, locked = "yes" }))
	end)
end)
