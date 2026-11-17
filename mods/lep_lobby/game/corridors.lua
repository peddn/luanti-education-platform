-- Builds the corridors and personal rooms of the lobby.

local load = lep_core.loader("lep_lobby")
local corridors = load("src/corridors")
local room_doors = load("game/doors")

local builder = {}

--- Builds one corridor with its rooms.
-- @param origin World position of the hall origin.
-- @param direction Corridor number, 1 to 4.
-- @param get_count Function returning the number of slots in use. It is
--   called when the map is ready, so a build never drops a room that was
--   assigned while it waited.
-- @param get_owner Function(slot) returning the owner name.
-- @param callback Called without arguments when done.
function builder.build(origin, direction, get_count, get_owner, callback)
	local wait_min, wait_max = corridors.bounds(direction, get_count())

	core.emerge_area(vector.add(origin, wait_min), vector.add(origin, wait_max),
			function(_, _, remaining)
		if remaining > 0 then
			return
		end

		local count = get_count()
		local rel_min, rel_max = corridors.bounds(direction, count)
		local min = vector.add(origin, rel_min)
		local max = vector.add(origin, rel_max)

		local ids = {
			[corridors.FLOOR] = core.get_content_id("lep_lobby:floor"),
			[corridors.GLASS] = core.get_content_id("lep_lobby:glass"),
			[corridors.LAMP] = core.get_content_id("lep_lobby:lamp"),
			[corridors.AIR] = core.CONTENT_AIR,
			[corridors.WALL] = core.get_content_id("lep_lobby:wall"),
			-- Signs are set afterwards, because they carry metadata.
			[corridors.SIGN] = core.CONTENT_AIR,
		}
		-- Doors are not touched here, so they stay open or closed. Missing
		-- doors are set afterwards.

		local vm = core.get_voxel_manip()
		local emin, emax = vm:read_from_map(min, max)
		local area = VoxelArea:new({ MinEdge = emin, MaxEdge = emax })
		local data = vm:get_data()

		for z = rel_min.z, rel_max.z do
			for y = rel_min.y, rel_max.y do
				for x = rel_min.x, rel_max.x do
					local kind = corridors.kind_at(x, y, z, count)
					if ids[kind] then
						data[area:index(origin.x + x, origin.y + y, origin.z + z)] = ids[kind]
					end
				end
			end
		end

		vm:set_data(data)
		vm:write_to_map(true)

		for slot = 0, count - 1 do
			local room = corridors.room(slot)
			if room.direction == direction then
				local pos = vector.add(origin, room.sign)
				core.set_node(pos, {
					name = "lep_lobby:room_sign",
					param2 = core.dir_to_wallmounted(room.sign_wall),
				})
				lep_core.signs.write(pos, corridors.sign_text(get_owner(slot)))
				room_doors.ensure(vector.add(origin, room.door), room.look_dir,
					get_owner(slot) or "")
			end
		end

		callback()
	end)
end

--- Builds all corridors one after the other.
function builder.build_all(origin, get_count, get_owner, callback)
	local function step(direction)
		if direction > corridors.DIRECTIONS then
			callback()
			return
		end
		builder.build(origin, direction, get_count, get_owner, function()
			step(direction + 1)
		end)
	end
	step(1)
end

return builder
