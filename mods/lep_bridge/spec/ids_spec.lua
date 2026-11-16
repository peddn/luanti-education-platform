local ids = dofile("mods/lep_bridge/src/ids.lua")

describe("lep_bridge ids", function()
	local function new_random(seed)
		return function(min, max)
			seed = (seed * 1103515245 + 12345) % 2147483648
			return min + math.floor(seed / 65536) % (max - min + 1)
		end
	end

	it("has the form of a UUID of version 4", function()
		local random = new_random(1)
		for _ = 1, 50 do
			local id = ids.uuid(random)
			assert.is_truthy(id:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-"
				.. "%x%x%x%x%x%x%x%x%x%x%x%x$"), id)
		end
	end)

	it("differs from call to call", function()
		local random = new_random(7)
		local seen = {}
		for _ = 1, 200 do
			local id = ids.uuid(random)
			assert.is_nil(seen[id])
			seen[id] = true
		end
	end)
end)
