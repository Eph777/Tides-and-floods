-- abm.lua
-- Cellular-automata water propagation ABMs for shore, offshore, and wave nodes

local abm_long_delay = 10
local abm_short_delay = 0.2

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

-- ============================================================
-- SHOREWATER ABM
-- ============================================================
minetest.register_abm({
	name = "realistic_rising_floods:shorewater_abm",
	nodenames = {"realistic_rising_floods:shorewater"},
	interval = abm_long_delay,
	chance = 1,
	catch_up = false,
	action = function(pos)
		local sealevel = realistic_rising_floods.sealevel or 1
		local cardinal_pos = {
			{x=pos.x+1, y=pos.y, z=pos.z},
			{x=pos.x-1, y=pos.y, z=pos.z},
			{x=pos.x, y=pos.y, z=pos.z+1},
			{x=pos.x, y=pos.y, z=pos.z-1}
		}

		local cardinal_node = {
			get_node(cardinal_pos[1]).name,
			get_node(cardinal_pos[2]).name,
			get_node(cardinal_pos[3]).name,
			get_node(cardinal_pos[4]).name
		}

		-- trigger receding tide
		if pos.y > sealevel then
			minetest.set_node(pos, {name = "realistic_rising_floods:wave"})
		-- trigger rising tide
		elseif pos.y <= sealevel then
			local count_water = 0
			for i = 1, 4 do
				if realistic_rising_floods.can_it_flood(cardinal_node[i]) then
					minetest.set_node(pos, {name = "realistic_rising_floods:wave"})
					break
				end
				if water_and_friends[cardinal_node[i]] then
					count_water = count_water + 1
				end
			end
			if count_water == 4 then
				minetest.set_node(pos, {name = "realistic_rising_floods:seawater"})
			end
		end
	end
})

-- ============================================================
-- OFFSHORE_WATER ABM
-- ============================================================
minetest.register_abm({
	name = "realistic_rising_floods:offshore_water_abm",
	nodenames = {"realistic_rising_floods:offshore_water"},
	interval = abm_long_delay,
	chance = 1,
	catch_up = false,
	action = function(pos)
		local sealevel = realistic_rising_floods.sealevel or 1
		local cardinal_pos = {
			{x=pos.x+1, y=pos.y, z=pos.z},
			{x=pos.x-1, y=pos.y, z=pos.z},
			{x=pos.x, y=pos.y, z=pos.z+1},
			{x=pos.x, y=pos.y, z=pos.z-1}
		}

		local cardinal_node = {
			get_node(cardinal_pos[1]).name,
			get_node(cardinal_pos[2]).name,
			get_node(cardinal_pos[3]).name,
			get_node(cardinal_pos[4]).name
		}

		-- if below sealevel then rise
		if pos.y < sealevel then
			minetest.set_node(pos, {name = "realistic_rising_floods:seawater"})
			for i = 1, 4 do
				if minetest.compare_block_status(cardinal_pos[i], "active") ~= true then
					minetest.set_node({x=pos.x, y=pos.y+1, z=pos.z}, {name = "realistic_rising_floods:wave"})
					break
				end
			end
		end

		-- if at sealevel then spread
		if pos.y == sealevel then
			for i = 1, 4 do
				if realistic_rising_floods.can_it_flood(cardinal_node[i]) then
					minetest.set_node(cardinal_pos[i], {name = "realistic_rising_floods:wave"})
				end
			end
		end
	end
})

-- ============================================================
-- WAVE PROPAGATION ENGINE (Globalstep Queue)
-- ============================================================
local wave_timer = 0
local abm_short_delay = 0.05 -- Run 20 times per second for ultra-fluid movement!

minetest.register_globalstep(function(dtime)
	wave_timer = wave_timer + dtime
	if wave_timer < abm_short_delay then return end
	wave_timer = 0

	local current_waves = realistic_rising_floods.active_waves or {}
	realistic_rising_floods.active_waves = {}

	local sealevel = realistic_rising_floods.sealevel or 1

	for hash, pos in pairs(current_waves) do
		local node = get_node(pos)
		if node.name == "realistic_rising_floods:wave" then
			local cardinal_pos = {
				{x=pos.x+1, y=pos.y, z=pos.z},
				{x=pos.x-1, y=pos.y, z=pos.z},
				{x=pos.x, y=pos.y, z=pos.z+1},
				{x=pos.x, y=pos.y, z=pos.z-1}
			}

			local cardinal_node = {
				get_node(cardinal_pos[1]).name,
				get_node(cardinal_pos[2]).name,
				get_node(cardinal_pos[3]).name,
				get_node(cardinal_pos[4]).name
			}

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

			local edge_x = pos.x % 16
			local edge_z = pos.z % 16

			-- TIDE GOES DOWN
			if pos.y > sealevel then
				minetest.set_node(pos, {name = "air"})
				
				-- Spread wave to neighbors to recede
				for i = 1, 4 do
					if water_and_friends[cardinal_node[i]] and cardinal_node[i] ~= "realistic_rising_floods:wave" then
						minetest.set_node(cardinal_pos[i], {name = "realistic_rising_floods:wave"})
					end
				end

				-- CHANGE NODES BELOW
				if get_node({x=pos.x, y=pos.y-1, z=pos.z}).name == "realistic_rising_floods:seawater" then
					if (pos.x % 16 == 0 or pos.x % 16 == 15) and (pos.z % 16 == 0 or pos.z % 16 == 15) then
						minetest.set_node({x=pos.x, y=pos.y-1, z=pos.z}, {name = "realistic_rising_floods:offshore_water"})
					else
						local shore_below = false
						for i = 1, 4 do
							if water_or_air[cardinal_down_node[i]] == nil then
								minetest.set_node({x=pos.x, y=pos.y-1, z=pos.z}, {name = "realistic_rising_floods:shorewater"})
								shore_below = true
								break
							end
						end
						if not shore_below then
							minetest.set_node({x=pos.x, y=pos.y-1, z=pos.z}, {name = "realistic_rising_floods:seawater"})
						end
					end
				end

			-- TIDE GOES UP
			elseif pos.y <= sealevel then
				-- look for floodable neighbors
				for i = 1, 4 do
					if realistic_rising_floods.can_it_flood(cardinal_node[i]) then
						-- floatable logic
						local float = minetest.get_item_group(cardinal_node[i], "float")
						if float >= 1 then
							local cardinal_pos_up = vector.add(cardinal_pos[i], vector.new(0, 1, 0))
							local cardinal_node_up = get_node(cardinal_pos_up).name
							if realistic_rising_floods.can_it_flood(cardinal_node_up) then
								minetest.set_node(cardinal_pos[i], {name = tostring(cardinal_node_up)})
								minetest.set_node(cardinal_pos_up, {name = cardinal_node[i]})
							end
						end

						minetest.set_node(cardinal_pos[i], {name = "realistic_rising_floods:wave"})
					end
				end

				-- Determine replacement for this current node
				if (edge_x == 0 or edge_x == 15) and (edge_z == 0 or edge_z == 15) then
					minetest.set_node(pos, {name = "realistic_rising_floods:offshore_water"})
				else
					local shore = false
					for j = 1, 4 do
						if water_or_air[cardinal_node[j]] == nil then
							minetest.set_node(pos, {name = "realistic_rising_floods:shorewater"})
							shore = true

							-- Splash effects
							if math.random(1, 3) == 1 then
								minetest.sound_play("default_water_footstep", {
									pos = pos,
									gain = 0.08,
									max_hear_distance = 12,
								}, true)

								minetest.add_particlespawner({
									amount = 3,
									time = 0.08,
									minpos = {x = pos.x - 0.4, y = pos.y + 0.4, z = pos.z - 0.4},
									maxpos = {x = pos.x + 0.4, y = pos.y + 0.6, z = pos.z + 0.4},
									minvel = {x = -0.3, y = 0.4, z = -0.3},
									maxvel = {x = 0.3, y = 1.0, z = 0.3},
									minacc = {x = 0, y = -4.0, z = 0},
									maxacc = {x = 0, y = -4.0, z = 0},
									minexptime = 0.4,
									maxexptime = 0.6,
									minsize = 0.5,
									maxsize = 1.2,
									texture = "bubble.png^[colorize:#ffffff:200",
									collisiondetection = true,
								})
							end
							break
						end
					end
					if not shore then
						minetest.set_node(pos, {name = "realistic_rising_floods:seawater"})
					end
				end

				-- Clean below the surface
				local node_below = get_node({x=pos.x, y=pos.y-1, z=pos.z}).name
				if node_below ~= "realistic_rising_floods:seawater" and water_and_friends[node_below] then
					minetest.set_node({x=pos.x, y=pos.y-1, z=pos.z}, {name = "realistic_rising_floods:seawater"})
				end

				-- if surrounded by seawater, become seawater
				local seawater = 0
				for i = 1, 4 do
					if water_and_friends[cardinal_node[i]] then
						seawater = seawater + 1
					end
				end
				if seawater == 4 then
					if (edge_x == 0 or edge_x == 15) and (edge_z == 0 or edge_z == 15) then
						minetest.set_node(pos, {name = "realistic_rising_floods:offshore_water"})
					else
						minetest.set_node(pos, {name = "realistic_rising_floods:seawater"})
					end
				end
			end
		end
	end
end)
