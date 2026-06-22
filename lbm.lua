-- lbm.lua
-- Load-time block modifiers to convert default water and catch up loaded mapblocks to sea level

local get_node = minetest.get_node

local water_or_air = {
	["air"] = true,
	["default:water_source"] = true,
	["default:water_flowing"] = true,
	["default:river_water_flowing"] = true,
	["realistic_rising_floods:seawater"] = true,
	["realistic_rising_floods:shorewater"] = true,
	["realistic_rising_floods:offshore_water"] = true,
	["realistic_rising_floods:wave"] = true,
	["tides:seawater"] = true,
	["tides:shorewater"] = true,
	["tides:offshore_water"] = true,
	["tides:wave"] = true,
	["ignore"] = true
}

local water_and_friends = {
	["default:water_source"] = true,
	["default:water_flowing"] = true,
	["default:river_water_flowing"] = true,
	["realistic_rising_floods:seawater"] = true,
	["realistic_rising_floods:shorewater"] = true,
	["realistic_rising_floods:offshore_water"] = true,
	["realistic_rising_floods:wave"] = true,
	["tides:seawater"] = true,
	["tides:shorewater"] = true,
	["tides:offshore_water"] = true,
	["tides:wave"] = true,
	["ignore"] = true
}

-- REPLACE SEA WATER AT GENERATION with realistic_rising_floods nodes
if realistic_rising_floods.settings.ocean.fix_generated_water then
	minetest.register_lbm({
		name = "realistic_rising_floods:water_source_lbm",
		nodenames = {"default:water_source"},
		run_at_every_load = true,
		action = function(pos)
			local check_node = {
				["east"]  = get_node({x=pos.x+1, y=pos.y, z=pos.z}).name,
				["west"]  = get_node({x=pos.x-1, y=pos.y, z=pos.z}).name,
				["up"]    = get_node({x=pos.x, y=pos.y+1, z=pos.z}).name,
				["down"]  = get_node({x=pos.x, y=pos.y-1, z=pos.z}).name,
				["north"] = get_node({x=pos.x, y=pos.y, z=pos.z+1}).name,
				["south"] = get_node({x=pos.x, y=pos.y, z=pos.z-1}).name
			}
			local cardinal = {"north", "south", "east", "west"}
			if check_node["up"] == "air" then
				for i = 1, 4 do
					if water_or_air[check_node[cardinal[i]]] == nil then
						minetest.set_node(pos, {name = "realistic_rising_floods:shorewater"})
						return
					end
				end
				local edge_x = pos.x % 16
				local edge_z = pos.z % 16
				if (edge_x == 0 or edge_x == 15) and (edge_z == 0 or edge_z == 15) then
					minetest.set_node(pos, {name = "realistic_rising_floods:offshore_water"})
					return
				end
			end
			minetest.set_node(pos, {name = "realistic_rising_floods:seawater"})
		end
	})
end

-- SEAWATER LBM
minetest.register_lbm({
	name = "realistic_rising_floods:seawater_lbm",
	nodenames = {"realistic_rising_floods:seawater"},
	run_at_every_load = true,
	action = function(pos)
		local sealevel = realistic_rising_floods.sealevel or 1
		local cardinal_down_pos = {
			{x=pos.x+1, y=pos.y-1, z=pos.z},
			{x=pos.x-1, y=pos.y-1, z=pos.z},
			{x=pos.x, y=pos.y-1, z=pos.z+1},
			{x=pos.x, y=pos.y-1, z=pos.z-1}
		}
		local cardinal_down_node = {
			get_node(cardinal_down_pos[1]).name,
			get_node(cardinal_down_pos[2]).name,
			get_node(cardinal_down_pos[3]).name,
			get_node(cardinal_down_pos[4]).name
		}

		if pos.y > sealevel then
			minetest.remove_node(pos)
			minetest.set_node(pos, {name = "air"})

			-- Change nodes below
			if pos.y == sealevel + 1 then
				if get_node({x=pos.x, y=pos.y-1, z=pos.z}).name == "realistic_rising_floods:seawater" then
					if (pos.x % 16 == 0 or pos.x % 16 == 15) and (pos.z % 16 == 0 or pos.z % 16 == 15) then
						minetest.set_node({x=pos.x, y=pos.y-1, z=pos.z}, {name = "realistic_rising_floods:offshore_water"})
						return
					end
					for i = 1, 4 do
						if water_or_air[cardinal_down_node[i]] == nil then
							minetest.set_node({x=pos.x, y=pos.y-1, z=pos.z}, {name = "realistic_rising_floods:shorewater"})
							return
						end
					end
				end
				return
			end
		end

		local node_above_pos = pos:offset(0, 1, 0)
		if get_node(node_above_pos).name ~= "ignore" then
			local node_above = get_node(node_above_pos).name
			local drawtype = minetest.registered_nodes[node_above] and minetest.registered_nodes[node_above].drawtype or "normal"
			if drawtype == "airlike" or drawtype == "flowingliquid" then
				if pos.y > sealevel then
					minetest.set_node({x=pos.x, y=pos.y+1, z=pos.z}, {name = "air"})
				elseif pos.y < sealevel then
					local tide_diff = sealevel - pos.y
					for i = 1, tide_diff do
						local node_above_i = get_node({x=pos.x, y=pos.y+i, z=pos.z}).name
						local def_above_i = minetest.registered_nodes[node_above_i]
						local drawtype_i = def_above_i and def_above_i.drawtype or "normal"
						if drawtype_i == "airlike" or drawtype_i == "flowingliquid" then
							minetest.set_node({x=pos.x, y=pos.y+i, z=pos.z}, {name = "realistic_rising_floods:seawater"})
						end
					end
				end
			end
		end
	end
})

-- SHOREWATER LBM
minetest.register_lbm({
	name = "realistic_rising_floods:shorewater_lbm",
	nodenames = {"realistic_rising_floods:shorewater"},
	run_at_every_load = true,
	action = function(pos, node)
		local sealevel = realistic_rising_floods.sealevel or 1
		local cardinal_down_pos = {
			{x=pos.x+1, y=pos.y-1, z=pos.z},
			{x=pos.x-1, y=pos.y-1, z=pos.z},
			{x=pos.x, y=pos.y-1, z=pos.z+1},
			{x=pos.x, y=pos.y-1, z=pos.z-1}
		}
		local cardinal_down_node = {
			get_node(cardinal_down_pos[1]).name,
			get_node(cardinal_down_pos[2]).name,
			get_node(cardinal_down_pos[3]).name,
			get_node(cardinal_down_pos[4]).name
		}

		if pos.y > sealevel then
			minetest.remove_node(pos)
			if pos.y == sealevel + 1 and water_and_friends[get_node({x=pos.x, y=pos.y-1, z=pos.z}).name] then
				for i = 1, 4 do
					if water_or_air[cardinal_down_node[i]] == nil then
						minetest.set_node({x=pos.x, y=pos.y-1, z=pos.z}, {name = "realistic_rising_floods:wave"})
						break
					else
						minetest.set_node({x=pos.x, y=pos.y-1, z=pos.z}, {name = "realistic_rising_floods:seawater"})
					end
				end
			end
		end

		local node_above = get_node({x=pos.x, y=pos.y+1, z=pos.z}).name
		local def_above = minetest.registered_nodes[node_above]
		local drawtype = def_above and def_above.drawtype or "normal"
		if drawtype == "airlike" or drawtype == "flowingliquid" then
			if pos.y < sealevel then
				local tide_diff = sealevel - pos.y
				for i = 1, tide_diff do
					local node_above_i = get_node({x=pos.x, y=pos.y+i, z=pos.z}).name
					local def_i = minetest.registered_nodes[node_above_i]
					local drawtype_i = def_i and def_i.drawtype or "normal"
					if drawtype_i == "airlike" or drawtype_i == "flowingliquid" then
						minetest.set_node({x=pos.x, y=pos.y+i, z=pos.z}, {name = "realistic_rising_floods:shorewater"})
					end
				end
			end
		end
	end
})

-- OFFSHORE_WATER LBM
minetest.register_lbm({
	name = "realistic_rising_floods:offshore_water_lbm",
	nodenames = {"realistic_rising_floods:offshore_water"},
	run_at_every_load = true,
	action = function(pos)
		local sealevel = realistic_rising_floods.sealevel or 1
		if pos.y > sealevel then
			minetest.remove_node(pos)
			if pos.y == sealevel + 1 and water_and_friends[get_node({x=pos.x, y=pos.y-1, z=pos.z}).name] then
				minetest.set_node({x=pos.x, y=pos.y-1, z=pos.z}, {name = "realistic_rising_floods:offshore_water"})
				return
			end
		end

		local node_above = get_node({x=pos.x, y=pos.y+1, z=pos.z}).name
		local def_above = minetest.registered_nodes[node_above]
		local drawtype = def_above and def_above.drawtype or "normal"
		if drawtype == "airlike" or drawtype == "flowingliquid" then
			if pos.y < sealevel then
				local tide_diff = sealevel - pos.y
				for i = 1, tide_diff do
					local node_above_i = get_node({x=pos.x, y=pos.y+i, z=pos.z}).name
					if realistic_rising_floods.can_it_flood(node_above_i) then
						minetest.set_node({x=pos.x, y=pos.y+i, z=pos.z}, {name = "realistic_rising_floods:offshore_water"})
					end
				end
			end
		end
	end
})

-- WAVE LBM
minetest.register_lbm({
	name = "realistic_rising_floods:wave_lbm",
	nodenames = {"realistic_rising_floods:wave"},
	run_at_every_load = true,
	action = function(pos)
		local sealevel = realistic_rising_floods.sealevel or 1
		if pos.y > sealevel then
			minetest.remove_node(pos)
			if pos.y == sealevel + 1 and water_and_friends[get_node({x=pos.x, y=pos.y-1, z=pos.z}).name] then
				minetest.set_node({x=pos.x, y=pos.y-1, z=pos.z}, {name = "realistic_rising_floods:seawater"})
				return
			end
		end

		local node_above = get_node({x=pos.x, y=pos.y+1, z=pos.z}).name
		local def_above = minetest.registered_nodes[node_above]
		local drawtype = def_above and def_above.drawtype or "normal"
		if drawtype == "airlike" or drawtype == "flowingliquid" then
			if pos.y < sealevel then
				minetest.set_node(pos, {name = "realistic_rising_floods:seawater"})
				local tide_diff = sealevel - pos.y
				for i = 1, tide_diff do
					local node_above_i = get_node({x=pos.x, y=pos.y+i, z=pos.z}).name
					if realistic_rising_floods.can_it_flood(node_above_i) then
						minetest.set_node({x=pos.x, y=pos.y+i, z=pos.z}, {name = "realistic_rising_floods:seawater"})
					end
				end
			end
		end
	end
})
