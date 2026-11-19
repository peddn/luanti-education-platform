-- Talks to the backend: sends the queued events and fetches jobs.
--
-- Two loops run side by side, each with one request at a time. Whatever
-- goes wrong, they try again later. Nothing in here ever stops the game.

local load = lep_core.loader("lep_bridge")
local queue_core = load("src/queue")
local ids = load("src/ids")
local backoff = load("src/backoff")
local messages = load("src/messages")
local store = load("game/store")

local M = {}

local queue = queue_core.new(store)
local job_handlers = {}
-- Kinds of jobs whose function answers later, through a callback.
local answers_later = {}

local http
local url = (core.settings:get("lep_bridge_url") or ""):gsub("%s", "")
local key = (core.settings:get("lep_bridge_key") or ""):gsub("%s", "")

-- State for people who look after the server.
local status = {
	active = false,
	reason = nil,
	last_contact = nil,
	send_failures = 0,
	poll_failures = 0,
	-- Events the backend did not know, since the start. More than none
	-- means the backend is older than the mods of this world.
	unknown = 0,
}

-- Seconds a request may take. Fetching jobs stays open on purpose.
local TIMEOUT = 15
local POLL_TIMEOUT = messages.WAIT_SECONDS + 10

--------------------------------------------------------------------------
-- Requests

-- Sends a request and calls callback(body) with the decoded answer, or
-- callback(nil, reason) if it failed.
local function request(method, path, body, timeout, callback)
	http.fetch({
		url = messages.url(url, path),
		method = method,
		timeout = timeout,
		extra_headers = {
			"Authorization: Bearer " .. key,
			"Content-Type: application/json",
		},
		data = body and core.write_json(body) or nil,
	}, function(result)
		if not result.succeeded or result.code ~= 200 then
			callback(nil, result.timeout and "timeout" or ("status " .. tostring(result.code)))
			return
		end
		local decoded = core.parse_json(result.data or "", nil, true)
		if type(decoded) ~= "table" then
			callback(nil, "the answer is not JSON")
			return
		end
		status.last_contact = os.time()
		callback(decoded)
	end)
end

--------------------------------------------------------------------------
-- Sending events

local sending = false

local function send_next()
	if sending or not status.active then
		return
	end
	local events = queue:peek(messages.MAX_BATCH)
	if #events == 0 then
		return
	end
	sending = true
	request("POST", "/events", messages.batch(events), TIMEOUT, function(body, reason)
		sending = false
		local results, err = nil, reason
		if body then
			results, err = messages.parse_results(body)
		end
		if not results then
			status.send_failures = status.send_failures + 1
			if status.send_failures == 1 then
				core.log("warning", "[lep_bridge] cannot send events (" .. tostring(err)
					.. "), " .. queue:size() .. " waiting. Trying again.")
			end
			core.after(backoff.delay(status.send_failures), send_next)
			return
		end

		if status.send_failures > 0 then
			core.log("action", "[lep_bridge] sending events works again")
		end
		status.send_failures = 0
		local answered = {}
		for index, result in ipairs(results) do
			answered[index] = result.id
			if result.outcome == "unknown" or result.outcome == "invalid" then
				core.log("warning", "[lep_bridge] the backend could not use event "
					.. result.id .. " (" .. result.outcome .. "), dropped")
			end
		end
		local counts = messages.count_outcomes(results)
		if counts.unknown > 0 then
			if status.unknown == 0 then
				-- Said once and loudly: single warnings are easy to miss, and
				-- what is dropped here does not come back.
				core.log("error", "[lep_bridge] THE BACKEND DOES NOT KNOW EVENTS OF THIS "
					.. "WORLD. It is probably older than the mods. Update and restart the "
					.. "backend first, then the worlds. Until then protocol entries are "
					.. "lost for the backend; they stay in the files of the world.")
			end
			status.unknown = status.unknown + counts.unknown
		end
		if queue:remove(answered) == 0 then
			-- An answer that fits none of the events sent: do not loop on it.
			core.log("error", "[lep_bridge] the backend answered for other events")
			status.send_failures = 1
			core.after(backoff.delay(1), send_next)
			return
		end
		send_next()
	end)
end

--- Puts an event into the queue. It is sent as soon as the backend can
-- be reached, and at once if it can.
-- @param kind What happened, as crates/protocol names it.
-- @param payload Table with the details, not empty.
function lep_bridge.send(kind, payload)
	local event = messages.event(ids.uuid(math.random), kind, os.time(), payload)
	local dropped = queue:push(event)
	if dropped > 0 then
		core.log("warning", "[lep_bridge] the queue is full, dropped the oldest "
			.. dropped .. " event(s)")
	end
	send_next()
end

--- Removes the waiting events a function picks. For an account that is
-- removed: nothing about it is sent any more.
-- @param matches Function(event) returning true for an event to drop.
-- @return how many events were removed
function lep_bridge._drop_events(matches)
	return queue:drop_where(matches)
end

--------------------------------------------------------------------------
-- Jobs

-- Results of the jobs done since the start, by id. A job the backend
-- hands out again, because the result did not arrive, is not done twice.
local done = {}

--- Registers the function that does jobs of one kind. It gets the
-- payload and returns true or false and a short message. A job can arrive
-- more than once over the lifetime of a world, so doing it twice must not
-- hurt.
function lep_bridge.register_job(kind, handler)
	assert(type(kind) == "string" and kind ~= "", "a job needs a kind")
	assert(type(handler) == "function", "a job needs a function")
	assert(not job_handlers[kind], "job '" .. kind .. "' is already registered")
	job_handlers[kind] = handler
end

--- Registers the function that does jobs of one kind that take a
-- moment. It gets the payload and a function finish(ok, message), which
-- it calls once when the job is done. Until then no other job is done.
function lep_bridge.register_slow_job(kind, handler)
	lep_bridge.register_job(kind, handler)
	answers_later[kind] = true
end

-- Does a job and calls callback(result).
local function run(job, callback)
	if done[job.id] then
		callback(done[job.id])
		return
	end
	local answered = false
	local function finish(ok, message)
		if answered then
			return
		end
		answered = true
		local result = messages.job_result(ok, message)
		core.log("action", "[lep_bridge] job " .. job.kind .. " " .. job.id .. ": "
			.. (result.ok and "done" or "failed") .. " " .. result.message)
		done[job.id] = result
		callback(result)
	end

	local handler = job_handlers[job.kind]
	if not handler then
		finish(false, "this world does not know the job '" .. job.kind .. "'")
		return
	end
	local no_error, ok, message = pcall(handler, job.payload, finish)
	if not no_error then
		core.log("error", "[lep_bridge] job " .. job.kind .. " failed: " .. tostring(ok))
		finish(false, "the job failed in the world")
	elseif not answers_later[job.kind] then
		finish(ok, message)
	end
end

local poll

-- Does the jobs one after the other and reports each result, then asks
-- for more.
local function work(jobs, index)
	local job = jobs[index]
	if not job then
		poll()
		return
	end
	run(job, function(result)
		request("POST", "/jobs/" .. job.id .. "/result", result, TIMEOUT, function()
			-- If the report got lost, the backend hands the job out again
			-- and the remembered result is reported then.
			work(jobs, index + 1)
		end)
	end)
end

poll = function()
	if not status.active then
		return
	end
	request("GET", "/jobs?wait=" .. messages.WAIT_SECONDS, nil, POLL_TIMEOUT,
		function(body, reason)
			local jobs, err = nil, reason
			if body then
				jobs, err = messages.parse_jobs(body)
			end
			if not jobs then
				status.poll_failures = status.poll_failures + 1
				if status.poll_failures == 1 then
					core.log("warning", "[lep_bridge] cannot reach the backend ("
						.. tostring(err) .. "). The game goes on, trying again.")
				end
				core.after(backoff.delay(status.poll_failures), poll)
				return
			end
			if status.poll_failures > 0 then
				core.log("action", "[lep_bridge] the backend is reachable again")
			end
			status.poll_failures = 0
			work(jobs, 1)
		end)
end

-- The job that only checks the way to the world and back.
lep_bridge.register_job(messages.JOB_PING, function()
	return true, "pong"
end)

--------------------------------------------------------------------------
-- State

--- Returns true if the bridge is set up and tries to reach the backend.
function lep_bridge.is_active()
	return status.active
end

--- Returns the state of the bridge for people who look after the server:
-- active, reason (why it is not active), url, queued, last_contact (time
-- of the last answer, or nil), failing (true if the last try failed),
-- unknown (events the backend did not know since the start).
function lep_bridge.get_status()
	return {
		active = status.active,
		reason = status.reason,
		url = url,
		queued = queue:size(),
		last_contact = status.last_contact,
		failing = status.send_failures > 0 or status.poll_failures > 0,
		unknown = status.unknown,
	}
end

--- Starts the bridge. Without address, key or network access it stays
-- quiet: events are queued and the game runs as ever.
-- @param http_api What core.request_http_api() returned, or nil.
function M.start(http_api)
	http = http_api
	if url == "" or key == "" then
		status.reason = "the settings lep_bridge_url and lep_bridge_key are not set"
	elseif not http then
		status.reason = "lep_bridge is missing in the setting secure.http_mods"
	else
		status.active = true
	end
	if not status.active then
		core.log("action", "[lep_bridge] not connected: " .. status.reason)
		return
	end
	core.log("action", "[lep_bridge] connecting to " .. url)

	core.register_on_mods_loaded(function()
		lep_bridge.send(messages.EVENT_WORLD_STARTED,
			messages.world_started(core.get_version().string, core.get_modnames()))
		core.after(0, poll)
	end)
end

return M
