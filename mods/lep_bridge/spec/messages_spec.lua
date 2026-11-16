local messages = dofile("mods/lep_bridge/src/messages.lua")
local schema = dofile("mods/lep_bridge/spec/schema.lua")

-- The same description the backend is built from.
local fits = schema.load("api/openapi.json")

describe("lep_bridge messages", function()
	it("builds addresses of the world interface", function()
		assert.are.equal("http://127.0.0.1:8080/api/world/v1/events",
			messages.url("http://127.0.0.1:8080", "/events"))
		assert.are.equal("https://lep.example/api/world/v1/jobs",
			messages.url("https://lep.example//", "/jobs"))
	end)

	it("builds events that fit the schema of the backend", function()
		local event = messages.event("id-1", messages.EVENT_WORLD_STARTED, 1700000000.7,
			messages.world_started("5.18.0", { "lep_core", "lep_bridge" }))
		assert.are.equal(1700000000, event.time)
		assert.is_true(fits("Event", event))
		assert.is_true(fits("WorldStarted", event.payload))
		assert.is_true(fits("EventBatch", messages.batch({ event, event })))
	end)

	it("builds job results that fit the schema of the backend", function()
		assert.is_true(fits("JobResult", messages.job_result(true, "pong")))
		assert.are.same({ ok = false, message = "" }, messages.job_result(nil, nil))
		assert.is_true(fits("JobResult", messages.job_result(false)))
	end)

	it("uses the limits of the backend", function()
		local json = require("dkjson")
		local file = assert(io.open("api/openapi.json"))
		local document = json.decode(file:read("*a"))
		file:close()
		-- The batch route exists under the path the bridge calls.
		assert.is_not_nil(document.paths["/api/world/v1/events"].post)
		assert.is_not_nil(document.paths["/api/world/v1/jobs"].get)
		assert.is_not_nil(document.paths["/api/world/v1/jobs/{id}/result"].post)
		assert.are.equal(100, messages.MAX_BATCH)
		assert.are.equal(25, messages.WAIT_SECONDS)
	end)

	it("the schema check itself notices what does not fit", function()
		assert.is_false(fits("Event", { id = "x", kind = "k", time = 1 }))
		assert.is_false(fits("Event", { id = 5, kind = "k", time = 1, payload = {} }))
		assert.is_false(fits("Event", { id = "x", kind = "k", time = 1.5, payload = {} }))
		assert.is_false(fits("EventResult", { id = "x", outcome = "maybe" }))
		assert.is_false(fits("WorldStarted", { engine = "5", mods = { 1, 2 } }))
	end)

	it("rejects events that are incomplete", function()
		assert.has_error(function() messages.event("", "k", 1, { a = 1 }) end)
		assert.has_error(function() messages.event("id", "", 1, { a = 1 }) end)
		assert.has_error(function() messages.event("id", "k", "now", { a = 1 }) end)
		assert.has_error(function() messages.event("id", "k", 1, {}) end)
	end)

	it("reads the answer to a batch", function()
		local body = { results = {
			{ id = "a", outcome = "accepted" },
			{ id = "b", outcome = "duplicate" },
			{ id = "c", outcome = "unknown" },
			{ id = "d", outcome = "invalid" },
		} }
		assert.is_true(fits("EventBatchResult", body))
		local results = messages.parse_results(body)
		assert.are.equal(4, #results)
		assert.are.same({ id = "c", outcome = "unknown" }, results[3])
	end)

	it("counts the outcomes of a batch", function()
		local counts = messages.count_outcomes(messages.parse_results({ results = {
			{ id = "a", outcome = "accepted" },
			{ id = "b", outcome = "unknown" },
			{ id = "c", outcome = "unknown" },
			{ id = "d", outcome = "duplicate" },
		} }))
		assert.are.same({ accepted = 1, duplicate = 1, unknown = 2, invalid = 0 }, counts)
		assert.are.same({ accepted = 0, duplicate = 0, unknown = 0, invalid = 0 },
			messages.count_outcomes({}))
	end)

	it("does not trust an answer it cannot read", function()
		assert.is_nil(messages.parse_results(nil))
		assert.is_nil(messages.parse_results({}))
		assert.is_nil(messages.parse_results({ results = { { id = "a", outcome = "maybe" } } }))
		assert.is_nil(messages.parse_results({ results = { { outcome = "accepted" } } }))
		assert.are.same({}, messages.parse_results({ results = {} }))
	end)

	it("reads the answer to a request for jobs", function()
		local body = { jobs = { { id = "j1", kind = "ping", payload = {} } } }
		assert.is_true(fits("JobList", body))
		local jobs = messages.parse_jobs(body)
		assert.are.same({ { id = "j1", kind = "ping", payload = {} } }, jobs)
		assert.are.same({}, messages.parse_jobs({ jobs = {} }))
		assert.are.same({}, messages.parse_jobs({}))
		assert.is_nil(messages.parse_jobs("text"))
		assert.is_nil(messages.parse_jobs({ jobs = { { kind = "ping" } } }))
		assert.is_nil(messages.parse_jobs({ jobs = { { id = "j1" } } }))
	end)
end)
