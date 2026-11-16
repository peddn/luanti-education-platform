local queue = dofile("mods/lep_bridge/src/queue.lua")

local function new_store()
	local data = {}
	return {
		get = function(key) return data[key] end,
		set = function(key, value) data[key] = value end,
		data = data,
	}
end

local function event(id)
	return { id = id, kind = "test", time = 1, payload = { n = 1 } }
end

local function ids(events)
	local list = {}
	for index, entry in ipairs(events) do
		list[index] = entry.id
	end
	return list
end

describe("lep_bridge queue", function()
	it("keeps events in the order they came", function()
		local q = queue.new(new_store())
		assert.are.equal(0, q:size())
		q:push(event("a"))
		q:push(event("b"))
		q:push(event("c"))
		assert.are.equal(3, q:size())
		assert.are.same({ "a", "b" }, ids(q:peek(2)))
		assert.are.same({ "a", "b", "c" }, ids(q:peek(10)))
		-- Looking removes nothing.
		assert.are.equal(3, q:size())
	end)

	it("removes what the backend answered for", function()
		local q = queue.new(new_store())
		for _, id in ipairs({ "a", "b", "c" }) do
			q:push(event(id))
		end
		assert.are.equal(2, q:remove({ "a", "b" }))
		assert.are.same({ "c" }, ids(q:peek(10)))
		assert.are.equal(1, q:size())
	end)

	it("stops removing at the first event without an answer", function()
		local q = queue.new(new_store())
		for _, id in ipairs({ "a", "b", "c" }) do
			q:push(event(id))
		end
		-- No answer for "a": nothing behind it may go either.
		assert.are.equal(0, q:remove({ "b", "c" }))
		assert.are.equal(3, q:size())
		assert.are.equal(0, q:remove({}))
	end)

	it("survives a restart", function()
		local store = new_store()
		local q = queue.new(store)
		q:push(event("a"))
		q:push(event("b"))
		q:remove({ "a" })

		local again = queue.new(store)
		assert.are.equal(1, again:size())
		assert.are.same({ "b" }, ids(again:peek(10)))
		again:push(event("c"))
		assert.are.same({ "b", "c" }, ids(again:peek(10)))
	end)

	it("drops the oldest events when it is full", function()
		local q = queue.new(new_store(), { limit = 3 })
		assert.are.equal(0, q:push(event("a")))
		q:push(event("b"))
		q:push(event("c"))
		assert.are.equal(1, q:push(event("d")))
		assert.are.same({ "b", "c", "d" }, ids(q:peek(10)))
	end)

	it("leaves nothing behind in the store", function()
		local store = new_store()
		local q = queue.new(store)
		q:push(event("a"))
		q:push(event("b"))
		q:remove({ "a", "b" })
		for key in pairs(store.data) do
			assert.is_nil(key:match("^event:"), "left over: " .. key)
		end
	end)

	it("gets over entries it cannot read", function()
		local store = new_store()
		local q = queue.new(store)
		q:push(event("a"))
		q:push(event("b"))
		store.data["event:1"] = "broken"
		assert.are.same({ "b" }, ids(q:peek(10)))
		assert.are.equal(1, q:size())

		store.data.head, store.data.tail = "nonsense", "5"
		assert.are.equal(4, queue.new(store):size())
		store.data.head, store.data.tail = "9", "5"
		assert.are.equal(0, queue.new(store):size())
	end)

	it("rejects events without an id and stores without get and set", function()
		local q = queue.new(new_store())
		assert.has_error(function() q:push({ kind = "test" }) end)
		assert.has_error(function() q:push({ id = "" }) end)
		assert.has_error(function() queue.new({}) end)
		assert.has_error(function() queue.new(new_store(), { limit = 0 }) end)
	end)
end)
