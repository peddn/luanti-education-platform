-- Chat commands of lep_desk.

local S = core.get_translator("lep_desk")

core.register_chatcommand("pult", {
	description = S("Open the teacher's desk"),
	privs = { [lep_desk.PRIV_VIEW] = true },
	func = function(name)
		if not lep_desk.open(name) then
			return false, S("You have to be in the game.")
		end
		return true
	end,
})
