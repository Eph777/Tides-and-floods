-- dynamics.lua
-- Phase 3: Dynamics and entity interaction

local settings = realistic_fluids.settings
local BLOCK_SIZE = 16

local function get_block_pos(pos)
	return {
		x = math.floor(pos.x / BLOCK_SIZE) * BLOCK_SIZE,
		y = math.floor(pos.y / BLOCK_SIZE) * BLOCK_SIZE,
		z = math.floor(pos.z / BLOCK_SIZE) * BLOCK_SIZE
	}
end

local function hash_pos(pos)
	return pos.x .. "," .. pos.y .. "," .. pos.z
end

local function get_fluid_data(pos)
	local bpos = get_block_pos(pos)
	local hash = hash_pos(bpos)
	local grid = realistic_fluids.grids[hash]
	
	if not grid then return 0.0, 0.0, 0.0 end
	
	local ly = math.floor(pos.y) - bpos.y
	local lx = math.floor(pos.x) - bpos.x
	local lz = math.floor(pos.z) - bpos.z
	
	local sim = grid.y_sims[ly]
	if not sim then return 0.0, 0.0, 0.0 end
	
	local rho = sim:get_density(lx, lz)
	local ux, uz = sim:get_velocity(lx, lz)
	
	return rho, ux, uz
end

-- 1. Apply LBM Velocity to Entities
minetest.register_globalstep(function(dtime)
	if settings.disable_lbm then return end
	
	for _, player in ipairs(minetest.get_connected_players()) do
		local pos = player:get_pos()
		-- Player's feet
		local rho, ux, uz = get_fluid_data(pos)
		
		if rho > 1.0 then
			-- Apply force to player
			-- Minetest allows adding velocity to players in Luanti 5.9+ via add_player_velocity
			-- or standard set_physics_override/add_velocity for entities
			local vel = player:get_velocity() or {x=0, y=0, z=0}
			local force_factor = 2.0 * dtime
			
			-- Simple integration
			local nvx = vel.x + ux * force_factor
			local nvz = vel.z + uz * force_factor
			
			-- Cap max push velocity
			if nvx*nvx + nvz*nvz < 25 then
				player:add_velocity({x = ux * force_factor, y = 0, z = uz * force_factor})
			end
		end
	end
	
	-- Note: A full implementation would iterate over all active Lua entities,
	-- but for performance we focus on players and items in fluid.
	for _, entity in pairs(core.luaentities) do
		local pos = entity.object:get_pos()
		if pos then
			local rho, ux, uz = get_fluid_data(pos)
			if rho > 1.0 then
				local force_factor = 3.0 * dtime
				entity.object:add_velocity({x = ux * force_factor, y = 0, z = uz * force_factor})
			end
		end
	end
end)

-- 2. Waterfall Detection and Particles
minetest.register_globalstep(function(dtime)
	if settings.disable_lbm or math.random() > 0.1 then return end -- Check less frequently
	
	for _, grid in pairs(realistic_fluids.grids) do
		if grid.active then
			for y = 1, BLOCK_SIZE - 1 do
				local sim_upper = grid.y_sims[y]
				local sim_lower = grid.y_sims[y-1]
				
				if sim_upper and not sim_lower then
					-- There is fluid above, but none directly below in this grid layer
					-- Scan for active falling streams
					for z = 0, BLOCK_SIZE - 1 do
						for x = 0, BLOCK_SIZE - 1 do
							local rho = sim_upper:get_density(x, z)
							if rho > 1.0 then
								-- Potential waterfall
								local wpos = {
									x = grid.block_pos.x + x,
									y = grid.block_pos.y + y,
									z = grid.block_pos.z + z
								}
								
								local ux, uz = sim_upper:get_velocity(x, z)
								
								minetest.add_particlespawner({
									amount = math.ceil(rho * 2),
									time = 1,
									minpos = {x=wpos.x - 0.4, y=wpos.y - 0.5, z=wpos.z - 0.4},
									maxpos = {x=wpos.x + 0.4, y=wpos.y - 0.5, z=wpos.z + 0.4},
									minvel = {x=ux - 0.2, y=-5, z=uz - 0.2},
									maxvel = {x=ux + 0.2, y=-10, z=uz + 0.2},
									minacc = {x=0, y=-9.8, z=0},
									maxacc = {x=0, y=-9.8, z=0},
									minexptime = 1,
									maxexptime = 3,
									minsize = 1,
									maxsize = 3,
									collisiondetection = true,
									collision_removal = true,
									vertical = true,
									texture = "default_water_flowing_animated.png",
								})
							end
						end
					end
				end
			end
		end
	end
end)

-- 3. Shore Erosion (Optional)
if settings.enable_erosion then
	local erosible_nodes = {
		["default:sand"] = "default:water_source",
		["default:dirt"] = "default:dirt_with_grass", -- Actually we just turn it to mud or water
	}

	minetest.register_globalstep(function(dtime)
		if math.random() > 0.05 then return end -- run infrequently
		
		for _, grid in pairs(realistic_fluids.grids) do
			if grid.active then
				for y = 0, BLOCK_SIZE - 1 do
					local sim = grid.y_sims[y]
					if sim then
						for z = 1, BLOCK_SIZE - 2 do
							for x = 1, BLOCK_SIZE - 2 do
								local idx = sim:get_index(x, z)
								if not sim.solid[idx] then
									local ux, uz = sim:get_velocity(x, z)
									local speed_sq = ux*ux + uz*uz
									if speed_sq > 0.5 then
										-- High velocity, test adjacent cells for erosion
										local adj = {
											{x=x+1, z=z}, {x=x-1, z=z},
											{x=x, z=z+1}, {x=x, z=z-1}
										}
										for _, a in ipairs(adj) do
											if sim.solid[sim:get_index(a.x, a.z)] then
												local wpos = {
													x = grid.block_pos.x + a.x,
													y = grid.block_pos.y + y,
													z = grid.block_pos.z + a.z
												}
												local node = minetest.get_node(wpos)
												if erosible_nodes[node.name] then
													minetest.set_node(wpos, {name = "default:water_source"})
													sim:set_solid(a.x, a.z, false)
													sim:add_source(a.x, a.z, 7.0)
												end
											end
										end
									end
								end
							end
						end
					end
				end
			end
		end
	end)
end
