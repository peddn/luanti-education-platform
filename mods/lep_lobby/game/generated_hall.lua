-- The generated hall. This is one "hall provider": it can build the hall
-- and knows its important spots. A hand-built hall would be a second
-- provider with the same two functions.

local load = lep_core.loader("lep_lobby")
local hall = load("src/hall")
local corridors = load("src/corridors")

local provider = {}

provider.version = hall.VERSION

--- Returns the important spots, see src/hall.lua, and in addition
-- `corridors`: a list of { start, dir } telling where the corridors to the
-- personal rooms begin and in which direction they run.
function provider.anchors(origin)
	local anchors = hall.anchors(origin)
	anchors.corridors = {}
	for index, entry in ipairs(corridors.starts()) do
		anchors.corridors[index] = {
			start = vector.add(origin, entry.start),
			dir = entry.dir,
		}
	end
	return anchors
end

--- Builds the hall around origin. Calls callback() when done.
function provider.build(origin, callback)
	local rel_min, rel_max = hall.bounds()
	local min = vector.add(origin, rel_min)
	local max = vector.add(origin, rel_max)

	core.emerge_area(min, max, function(_, _, remaining)
		if remaining > 0 then
			return
		end

		local ids = {
			[hall.FLOOR] = core.get_content_id("lep_lobby:floor"),
			[hall.GLASS] = core.get_content_id("lep_lobby:glass"),
			[hall.LAMP] = core.get_content_id("lep_lobby:lamp"),
			[hall.AIR] = core.CONTENT_AIR,
			[hall.FIREFLY] = core.get_content_id("lep_lobby:firefly"),
		}
		local butterfly_ids = {}
		for colour, name in ipairs(lep_lobby.BUTTERFLY_NODES) do
			butterfly_ids[colour] = core.get_content_id(name)
		end

		local vm = core.get_voxel_manip()
		local emin, emax = vm:read_from_map(min, max)
		local area = VoxelArea:new({ MinEdge = emin, MaxEdge = emax })
		local data = vm:get_data()

		for z = rel_min.z, rel_max.z do
			for y = rel_min.y, rel_max.y do
				for x = rel_min.x, rel_max.x do
					local kind, colour = hall.kind_at(x, y, z)
					if kind then
						data[area:index(origin.x + x, origin.y + y, origin.z + z)] =
							ids[kind] or butterfly_ids[colour]
					end
				end
			end
		end

		vm:set_data(data)
		vm:write_to_map(true)

		-- Until the portal exists, a lamp marks and lights its place.
		core.set_node(hall.anchors(origin).portal, { name = "lep_lobby:lamp" })

		callback()
	end)
end

return provider
