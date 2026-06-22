-- voxelmanip.lua
-- Replace default mapgen water with realistic_rising_floods water nodes during generation

local c_water_or_air = {}

minetest.register_on_mods_loaded(function()
	c_water_or_air = {
		[minetest.get_content_id("air")] = true,
		[minetest.get_content_id("default:water_source")] = true,
		[minetest.get_content_id("default:water_flowing")] = true,
		[minetest.get_content_id("default:river_water_flowing")] = true,
		[minetest.get_content_id("realistic_rising_floods:offshore_water")] = true,
		[minetest.get_content_id("realistic_rising_floods:wave_offshorewater")] = true,
		[minetest.get_content_id("realistic_rising_floods:seawater")] = true,
		[minetest.get_content_id("realistic_rising_floods:wave")] = true,
		[minetest.get_content_id("realistic_rising_floods:shorewater")] = true,
		[minetest.get_content_id("realistic_rising_floods:wave_shorewater")] = true,
		[minetest.get_content_id("ignore")] = true
	}
end)

minetest.register_on_generated(function(minp, maxp, blockseed)
	local vm, emin, emax = minetest.get_mapgen_object("voxelmanip")
	local data = vm:get_data()
	local c_air = minetest.CONTENT_AIR
	local c_water = minetest.get_content_id("mapgen_water_source")
	local c_offshorewater = minetest.get_content_id("realistic_rising_floods:offshore_water")
	local c_shorewater = minetest.get_content_id("realistic_rising_floods:shorewater")
	local c_seawater = minetest.get_content_id("realistic_rising_floods:seawater")
	local area = VoxelArea:new{
		MinEdge = emin,
		MaxEdge = emax
	}

	for z = minp.z, maxp.z do
		for y = minp.y, maxp.y do
			local vi = area:index(minp.x, y, z)
			for x = minp.x, maxp.x do
				if data[vi] == c_water then
					local check_node = {
						["east"] = data[area:index(x+1, y, z)],
						["west"] = data[area:index(x-1, y, z)],
						["up"]   = data[area:index(x, y+1, z)],
						["north"] = data[area:index(x, y, z+1)],
						["south"] = data[area:index(x, y, z-1)]
					}
					local cardinal = {"north", "south", "east", "west"}
					-- first turn any water into seawater
					data[vi] = c_seawater
					if check_node["up"] == c_air then
						-- then if node is at corner of mapblock, become offshore water
						if (x % 16 == 0 or x % 16 == 15) and (z % 16 == 0 or z % 16 == 15) then
							data[vi] = c_offshorewater
						end
						-- if next to a node that's neither air or water, become shorewater
						for i = 1, 4 do
							if c_water_or_air[check_node[cardinal[i]]] == nil then
								data[vi] = c_shorewater
								break
							end
						end
					end
				end
				vi = vi + 1
			end
		end
	end
	vm:set_data(data)
	vm:write_to_map(true)
end)
