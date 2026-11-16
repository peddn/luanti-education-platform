-- The tab "Web access" of the desk: a teacher enters the address they
-- log in with at the web application.
--
-- The desk does not talk to the backend. A provider, in practice the
-- bridge, passes requests on and brings back how a web access stands.
-- The world keeps a copy with shortened addresses, never a whole one.

local load = lep_core.loader("lep_desk")
local web_access = load("src/web_access")
local S = core.get_translator("lep_desk")

local TAB = "lep_desk:web_access"
local KEY_PREFIX = "web_access:"
-- Seconds between two looks at who holds the privilege. Changes through
-- the chat commands are noticed at once.
local CHECK_INTERVAL = 30

lep_desk.PRIV_WEB = "lep_web_access"

core.register_privilege(lep_desk.PRIV_WEB, {
	description = "Can set up their own access to the web application at the teacher's desk",
	give_to_singleplayer = false,
	give_to_admin = true,
})

local mod_storage = core.get_mod_storage()

--------------------------------------------------------------------------
-- The copy of how each web access stands

local function read(account)
	local text = mod_storage:get_string(KEY_PREFIX .. account)
	local stored = text ~= "" and core.parse_json(text) or nil
	if type(stored) ~= "table" then
		return web_access.record(nil, nil)
	end
	return web_access.record(stored.address, stored.pending)
end

local function write(account, record)
	if web_access.status(record) == web_access.NONE then
		mod_storage:set_string(KEY_PREFIX .. account, "")
	else
		mod_storage:set_string(KEY_PREFIX .. account, core.write_json(record))
	end
end

--- Returns how the web access of an account stands, as far as this
-- world knows: status ("none", "pending" or "confirmed"), address (the
-- confirmed address, shortened, or nil) and pending (the address that
-- waits for its confirmation, shortened, or nil).
function lep_desk.get_web_access(account)
	local record = read(account)
	return { status = web_access.status(record), address = record.address,
		pending = record.pending }
end

--- Notes how the web access of an account stands. Called by the
-- provider with what the backend says. Addresses are shortened.
function lep_desk.set_web_access(account, address, pending)
	assert(type(account) == "string" and account ~= "", "set_web_access: account is missing")
	write(account, web_access.record(address, pending))
	lep_desk.refresh_tab(account, TAB)
end

--------------------------------------------------------------------------
-- The provider and who holds the privilege

local provider

--- Registers what connects the desk to the web application.
-- @param def Table with:
--   is_available  function() returning true if requests can be passed on
--   request       function(kind, account, email) that passes a request
--                 on. `kind` is "set", "resend" or "remove", `email` the
--                 checked address for "set".
function lep_desk.register_web_access_provider(def)
	assert(type(def) == "table" and type(def.is_available) == "function"
		and type(def.request) == "function", "a web access provider needs two functions")
	assert(not provider, "there is already a web access provider")
	provider = def
end

local function is_available()
	return provider ~= nil and provider.is_available() == true
end

--- Returns the sorted names of all accounts of this world that hold the
-- privilege for web access, online or not.
function lep_desk.get_web_access_holders()
	local holders = {}
	for name in core.get_auth_handler().iterate() do
		if core.get_player_privs(name)[lep_desk.PRIV_WEB] then
			holders[#holders + 1] = name
		end
	end
	table.sort(holders)
	return holders
end

local dispatcher = lep_core.events.new(function(event_name, err)
	core.log("error", "[lep_desk] callback for " .. event_name .. " failed: "
		.. tostring(err))
end)

--- Registers a function(holders) that is called when the list of
-- accounts that hold the privilege for web access has changed.
lep_desk.register_on_web_access_holders_changed = dispatcher:registrar("holders_changed")

local known_holders

-- Looks who holds the privilege and reports a change.
local function check_holders()
	local holders = lep_desk.get_web_access_holders()
	if known_holders and web_access.same_names(known_holders, holders) then
		return
	end
	local first_look = known_holders == nil
	known_holders = holders
	if not first_look then
		dispatcher:emit("holders_changed", holders)
	end
end

core.register_on_mods_loaded(function()
	core.after(0, check_holders)
end)

local function check_soon(_, _, privilege)
	if privilege == lep_desk.PRIV_WEB then
		core.after(0, check_holders)
	end
end
core.register_on_priv_grant(check_soon)
core.register_on_priv_revoke(check_soon)

local since_check = 0
core.register_globalstep(function(dtime)
	since_check = since_check + dtime
	if since_check >= CHECK_INTERVAL then
		since_check = 0
		check_holders()
	end
end)

--------------------------------------------------------------------------
-- Requests

-- Per teacher: message (why the last request did not work, or what the
-- next click does), asked (time of the last request for a mail),
-- confirm_remove (true after the first click on "Remove"), draft (an
-- address that was refused, so the teacher can correct it).
local sessions = {}

local function session_of(teacher_name)
	sessions[teacher_name] = sessions[teacher_name] or { message = "" }
	return sessions[teacher_name]
end

core.register_on_leaveplayer(function(player)
	sessions[player:get_player_name()] = nil
end)

--- Passes a request of a teacher about their own web access on.
-- Everything is checked here again.
-- @param kind "set", "resend" or "remove"
-- @param email The address, for "set".
-- @return true, or false and why not: "privilege", "unavailable",
--   "email", "nothing_pending" or "too_soon"
function lep_desk.request_web_access(teacher_name, kind, email)
	if not core.check_player_privs(teacher_name, { [lep_desk.PRIV_WEB] = true }) then
		return false, "privilege"
	end
	if not is_available() then
		return false, "unavailable"
	end
	local record = read(teacher_name)
	local session = session_of(teacher_name)
	local now = os.time()
	local checked
	if kind == web_access.SET then
		checked = web_access.check_email(email)
		if not checked then
			return false, "email"
		end
	elseif kind == web_access.RESEND then
		if not record.pending then
			return false, "nothing_pending"
		end
		if not web_access.may_ask_for_mail(session.asked, now) then
			return false, "too_soon"
		end
	elseif kind ~= web_access.REMOVE then
		error("unknown web access request '" .. tostring(kind) .. "'")
	end

	-- The backend only listens to accounts it knows as teachers. A
	-- privilege that was just given is reported first.
	check_holders()
	if kind ~= web_access.REMOVE then
		session.asked = now
	end
	provider.request(kind, teacher_name, checked)
	lep_desk.record(teacher_name, "web_access:" .. kind)
	write(teacher_name, web_access.after_request(record, kind, checked))
	return true
end

--------------------------------------------------------------------------
-- The tab

local REASONS = {
	privilege = S("You may not set up web access."),
	unavailable = S("This world is not connected to the web application."),
	email = S("That is not an e-mail address."),
	nothing_pending = S("No address is waiting for its confirmation."),
	too_soon = S("A mail was sent a moment ago. Please wait a minute."),
}

local function build(fs, teacher_name, area)
	local session = session_of(teacher_name)
	local info = lep_desk.get_web_access(teacher_name)
	local x, y = area.x, area.y + 0.3

	fs:label(x, y, S("Web access for @1", teacher_name))
	y = y + 0.7
	if not is_available() then
		fs:label(x, y, S("This world is not connected to the web application."))
		fs:label(x, y + 0.5, S("Web access cannot be set up here right now."))
		return
	end

	if info.status == web_access.CONFIRMED then
		fs:label(x, y, S("Status: confirmed, @1", info.address))
	elseif info.status == web_access.PENDING then
		fs:label(x, y, S("Status: waiting for confirmation"))
	else
		fs:label(x, y, S("Status: not set up"))
	end
	y = y + 0.5
	if info.pending then
		fs:label(x, y, S("A mail with a link went to @1. Open the link to confirm the address.",
			info.pending))
		y = y + 0.5
		fs:label(x, y, S("The link works for 15 minutes."))
		y = y + 0.5
		if info.address then
			fs:label(x, y, S("Until then @1 stays valid.", info.address))
			y = y + 0.5
		end
	end

	y = y + 0.6
	fs:field(x, y, 9, 0.8, "email", info.status == web_access.NONE
		and S("Your official e-mail address") or S("New e-mail address"), session.draft or "")
	fs:element("field_close_on_enter", "email", "false")
	fs:button(x + 9.2, y, 4.5, 0.8, "web_set", info.status == web_access.NONE
		and S("Enter address") or S("Change address"))
	y = y + 1.3
	if info.pending then
		fs:button(x, y, 6, 0.8, "web_resend", S("Send the mail again"))
	end
	if info.status ~= web_access.NONE then
		fs:button(x + 6.3, y, 6, 0.8, "web_remove", session.confirm_remove
			and S("Really remove: click again") or S("Remove web access"))
	end
	y = y + 1.4
	fs:label(x, y, session.message)

	fs:label(x, area.y + area.height - 0.9,
		S("The address is stored in the web application, not in this world."))
	fs:label(x, area.y + area.height - 0.4,
		S("With it you log in there: you get a link by mail, there is no password."))
end

local function on_fields(teacher_name, fields)
	local session = session_of(teacher_name)
	local remove_confirmed = session.confirm_remove
	session.confirm_remove = nil
	session.message = ""

	local kind, email
	if fields.web_set or fields.key_enter_field == "email" then
		kind, email = web_access.SET, fields.email
	elseif fields.web_resend then
		kind = web_access.RESEND
	elseif fields.web_remove then
		if not remove_confirmed then
			session.confirm_remove = true
			session.message = S("This removes your address and your web access.")
			return
		end
		kind = web_access.REMOVE
	else
		return
	end

	local ok, reason = lep_desk.request_web_access(teacher_name, kind, email)
	-- What worked shows in the status. Only a failure needs a line.
	session.message = ok and "" or (REASONS[reason] or S("That did not work."))
	session.draft = nil
	if not ok and reason == "email" and type(email) == "string" then
		session.draft = email:sub(1, web_access.MAX_EMAIL)
	end
end

lep_desk.register_tab(TAB, {
	title = S("Web access"),
	privilege = lep_desk.PRIV_WEB,
	build = build,
	on_fields = on_fields,
})
