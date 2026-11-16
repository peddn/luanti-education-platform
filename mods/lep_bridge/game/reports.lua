-- Reports the state of the students and the protocols to the backend.
--
-- This is the one place that knows both sides: the mods that hold the
-- data and the shapes the backend expects. The learning modules, the
-- desk and the chat know nothing about the backend. The world writes,
-- the backend mirrors: nothing here ever changes the state of a student.

local load = lep_core.loader("lep_bridge")
local reports = load("src/reports")

local SYNCED_KEY = "state_synced"
local mod_storage = core.get_mod_storage()

local has_progress = core.global_exists("lep_progress")
local has_trophies = core.global_exists("lep_trophies")

-- Texts for people leave the world in its language. Titles are
-- translatable texts, and the backend has no translations.
local function plain(text)
	return core.get_translated_string("de", tostring(text))
end

local function send_modules()
	local list = {}
	for index, module_id in ipairs(lep_progress.get_module_ids()) do
		local module = lep_progress.get_module(module_id)
		local levels = lep_progress.get_levels(module_id)
		for _, level in ipairs(levels) do
			for _, task in ipairs(level.tasks) do
				task.title = plain(task.title)
			end
		end
		list[index] = { id = module_id, title = plain(module.title), levels = levels }
	end
	lep_bridge.send(reports.EVENT_MODULES, reports.modules(list))
end

local function send_progress(player_name, module_id)
	local info = lep_progress.get_progress(player_name, module_id)
	if info then
		lep_bridge.send(reports.EVENT_PROGRESS, reports.progress(player_name, info))
	end
end

local function send_trophies(player_name)
	local list = {}
	for index, id in ipairs(lep_trophies.get_earned(player_name)) do
		local trophy = lep_trophies.get_trophy(id)
		list[index] = { id = id, title = plain(trophy.title), material = trophy.material }
	end
	lep_bridge.send(reports.EVENT_TROPHIES, reports.trophies(player_name, list))
end

-- Sends the whole state of all students the world knows.
local function send_everything()
	local count = 0
	if has_progress then
		send_modules()
		local module_ids = lep_progress.get_module_ids()
		for _, player_name in ipairs(lep_progress.get_players()) do
			for _, module_id in ipairs(module_ids) do
				send_progress(player_name, module_id)
			end
			count = count + 1
		end
	end
	if has_trophies then
		for _, player_name in ipairs(lep_trophies.get_players()) do
			send_trophies(player_name)
		end
	end
	core.log("action", "[lep_bridge] queued the whole state of " .. count .. " student(s)")
	return count
end

-- Every change of the state of a student is reported as the new state.
if has_progress then
	lep_progress.register_on_state_changed(send_progress)
end
if has_trophies then
	lep_trophies.register_on_awarded(send_trophies)
end

-- Every entry of a protocol is passed on.
lep_core.protocols.register_on_append(function(name, record)
	local payload = reports.protocol(name, record)
	if payload then
		lep_bridge.send(reports.EVENT_PROTOCOL, payload)
	end
end)

-- The backend can ask for the whole state again.
lep_bridge.register_job(reports.JOB_SYNC_STATE, function()
	return true, "queued the state of " .. send_everything() .. " student(s)"
end)

core.register_on_mods_loaded(function()
	if not lep_bridge.is_active() then
		return
	end
	-- One step later: the translations of the titles are loaded by then.
	core.after(0, function()
		if mod_storage:get_int(SYNCED_KEY) ~= 1 then
			-- First contact: the backend knows nothing about this world yet.
			send_everything()
			mod_storage:set_int(SYNCED_KEY, 1)
		elseif has_progress then
			-- The modules may have changed with an update of the mods.
			send_modules()
		end
	end)
end)
