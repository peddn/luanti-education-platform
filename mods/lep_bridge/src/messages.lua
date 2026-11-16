-- The messages between world and backend, as Lua tables. Pure Lua, no
-- engine calls.
--
-- Their shape is defined once, in crates/protocol. The tests of this
-- file check what is built here against api/openapi.json.

local messages = {}

-- Most events in one request, as the backend allows.
messages.MAX_BATCH = 100
-- Seconds a request for jobs stays open, as the backend allows.
messages.WAIT_SECONDS = 25

messages.EVENT_WORLD_STARTED = "world_started"
messages.JOB_PING = "ping"

-- What the backend can say about an event. In every case the world may
-- forget the event.
messages.OUTCOMES = { accepted = true, duplicate = true, unknown = true, invalid = true }

--- Returns the address of a path of the world interface.
-- @param base Address of the backend, for example "http://127.0.0.1:8080".
function messages.url(base, path)
	return (base:gsub("/+$", "")) .. "/api/world/v1" .. path
end

--- Builds an event.
-- @param payload Table with the details. It must not be empty, because an
--   empty Lua table cannot say whether it is a list or an object.
function messages.event(id, kind, time, payload)
	assert(type(id) == "string" and id ~= "", "an event needs an id")
	assert(type(kind) == "string" and kind ~= "", "an event needs a kind")
	assert(type(time) == "number", "an event needs a time")
	assert(type(payload) == "table" and next(payload) ~= nil, "an event needs a payload")
	return { id = id, kind = kind, time = math.floor(time), payload = payload }
end

--- Builds the body of a request that sends events.
function messages.batch(events)
	return { events = events }
end

--- Builds the payload of the event "world_started".
-- @param mods List of the names of the loaded mods.
function messages.world_started(engine, mods)
	return { engine = tostring(engine), mods = mods }
end

--- Builds the body of a request that reports how a job went.
function messages.job_result(ok, message)
	return { ok = ok == true, message = tostring(message or "") }
end

--- Reads the answer to a batch.
-- @param body The decoded answer.
-- @return list of { id, outcome }, or nil and an error message
function messages.parse_results(body)
	if type(body) ~= "table" or type(body.results) ~= "table" then
		return nil, "the answer has no results"
	end
	local results = {}
	for index, entry in ipairs(body.results) do
		if type(entry) ~= "table" or type(entry.id) ~= "string"
				or not messages.OUTCOMES[entry.outcome] then
			return nil, "result " .. index .. " cannot be read"
		end
		results[index] = { id = entry.id, outcome = entry.outcome }
	end
	return results
end

--- Reads the answer to a request for jobs.
-- @return list of { id, kind, payload }, or nil and an error message
function messages.parse_jobs(body)
	if type(body) ~= "table" then
		return nil, "the answer cannot be read"
	end
	-- An empty list may arrive as nothing at all.
	local list = body.jobs or {}
	if type(list) ~= "table" then
		return nil, "the answer has no jobs"
	end
	local jobs = {}
	for index, entry in ipairs(list) do
		if type(entry) ~= "table" or type(entry.id) ~= "string" or entry.id == ""
				or type(entry.kind) ~= "string" then
			return nil, "job " .. index .. " cannot be read"
		end
		jobs[index] = {
			id = entry.id,
			kind = entry.kind,
			payload = type(entry.payload) == "table" and entry.payload or {},
		}
	end
	return jobs
end

return messages
