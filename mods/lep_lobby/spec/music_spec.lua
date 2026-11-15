local music = dofile("mods/lep_lobby/src/music.lua")

local LOBBY = "test:lobby"

describe("lep_lobby music", function()
	it("starts when a player arrives in the lobby", function()
		assert.are.equal(music.START, music.action(LOBBY, LOBBY, false))
	end)

	it("does not start twice", function()
		assert.is_nil(music.action(LOBBY, LOBBY, true))
	end)

	it("stops when a player goes somewhere else", function()
		assert.are.equal(music.STOP, music.action(LOBBY, "test:wilderness", true))
	end)

	it("stops when a player leaves the game", function()
		assert.are.equal(music.STOP, music.action(LOBBY, nil, true))
	end)

	it("does nothing outside the lobby without music", function()
		assert.is_nil(music.action(LOBBY, "test:wilderness", false))
		assert.is_nil(music.action(LOBBY, nil, false))
	end)
end)
