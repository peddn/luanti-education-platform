-- The attention mode at the teacher's desk.

local S = core.get_translator("lep_attention")

lep_attention.PRIVILEGE = "lep_set_attention"

core.register_privilege(lep_attention.PRIVILEGE, {
	description = "Can put students into the attention mode",
	give_to_singleplayer = false,
	give_to_admin = true,
})

lep_desk.register_student_note(function(student)
	return lep_attention.is_active(student) and S("attention") or nil
end)

local GROUP = S("Attention")

lep_desk.register_action("lep_attention:on", {
	title = S("Switch on"),
	privilege = lep_attention.PRIVILEGE,
	group = GROUP,
	run = function(_, targets, text)
		local count = 0
		for _, student in ipairs(targets) do
			if lep_attention.start(student, text) then
				count = count + 1
			end
		end
		return S("Attention mode on: @1 of @2", count, #targets)
	end,
})

lep_desk.register_action("lep_attention:off", {
	title = S("Switch off"),
	privilege = lep_attention.PRIVILEGE,
	group = GROUP,
	run = function(_, targets)
		local count = 0
		for _, student in ipairs(targets) do
			if lep_attention.stop(student) then
				count = count + 1
			end
		end
		return S("Attention mode off: @1 of @2", count, #targets)
	end,
})
