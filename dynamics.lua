-- dynamics.lua
-- Phase 3: Dynamics and entity interaction (SWE)

local settings = realistic_fluids.settings
local BLOCK_SIZE = 16

local function get_block_pos(pos)
	return {
		x = math.floor(pos.x / BLOCK_SIZE) * BLOCK_SIZE,
		y = 0,
		z = math.floor(pos.z / BLOCK_SIZE) * BLOCK_SIZE
	}
end

local function hash_pos(pos)
	return pos.x .. "," .. pos.z
end

local function get_fluid_data(pos)
	local bpos = get_block_pos(pos)
	local hash = hash_pos(bpos)
	local grid = realistic_fluids.grids[hash]
	
	if not grid then return 0.0, 0.0, 0.0, 0.0 end
	
	local lx = math.floor(pos.x) - bpos.x
	local lz = math.floor(pos.z) - bpos.z
	
	local sim = grid.sim
	if not sim then return 0.0, 0.0, 0.0, 0.0 end
	
	local h = sim:get_water_height(lx, lz)
	local ux, uz = sim:get_velocity(lx, lz)
	
	-- We also need to know if the entity is actually IN the water vertically
	local base_y = grid.base_y[sim:get_index(lx, lz)] or 0
	
	return h, ux, uz, base_y
end

-- 1. Apply SWE Velocity to Entities
minetest.register_globalstep(function(dtime)
	if settings.disable_lbm then return end
	
	for _, player in ipairs(minetest.get_connected_players()) do
		local pos = player:get_pos()
		local h, ux, uz, base_y = get_fluid_data(pos)
		
		-- Check if player is below the water surface
		if h > 0.5 and pos.y >= base_y and pos.y <= base_y + h + 1.0 then
			local vel = player:get_velocity() or {x=0, y=0, z=0}
			local force_factor = 2.0 * dtime
			
			local nvx = vel.x + ux * force_factor
			local nvz = vel.z + uz * force_factor
			
			local surface_y = base_y + h
			local depth = surface_y - pos.y
			local buoyant_y = 0
			if depth > 0.5 then
				buoyant_y = depth * 2.0 * dtime
			end
			
			if nvx*nvx + nvz*nvz < 25 then
				player:add_velocity({x = ux * force_factor, y = buoyant_y, z = uz * force_factor})
			end
		end
	end
	
	for _, entity in pairs(core.luaentities) do
		local pos = entity.object:get_pos()
		if pos then
			local h, ux, uz, base_y = get_fluid_data(pos)
			if h > 0.5 and pos.y >= base_y and pos.y <= base_y + h + 1.0 then
				local force_factor = 3.0 * dtime
				
				local surface_y = base_y + h
				local depth = surface_y - pos.y
				local buoyant_y = 0
				if depth > 0.2 then
					buoyant_y = depth * 4.0 * dtime
				end
				
				entity.object:add_velocity({x = ux * force_factor, y = buoyant_y, z = uz * force_factor})
			end
		end
	end
end)

-- 2. Waterfall Detection
minetest.register_globalstep(function(dtime)
	if settings.disable_lbm or math.random() > 0.1 then return end
	
	for _, grid in pairs(realistic_fluids.grids) do
		if grid.active then
			local sim = grid.sim
			for z = 1, BLOCK_SIZE - 2 do
				for x = 1, BLOCK_SIZE - 2 do
					local h = sim:get_water_height(x, z)
					if h > 0.5 then
						local idx = sim:get_index(x, z)
						local b = grid.base_y[idx]
						
						-- Check neighbors for a steep drop
						local adj = {{x=x+1, z=z}, {x=x-1, z=z}, {x=x, z=z+1}, {x=x, z=z-1}}
						for _, a in ipairs(adj) do
							local aidx = sim:get_index(a.x, a.z)
							local ab = grid.base_y[aidx]
							if ab and (b - ab) > 2.0 then
								-- Waterfall!
								local wpos = {
									x = grid.block_pos.x + x,
									y = b + h,
									z = grid.block_pos.z + z
								}
								
								local ux, uz = sim:get_velocity(x, z)
								
								minetest.add_particlespawner({
									amount = math.ceil(h * 2),
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
								break
							end
						end
					end
				end
			end
		end
	end
end)

-- 3. Shore Erosion
if settings.enable_erosion then
	local erosible_nodes = {
		["default:sand"] = true,
		["default:dirt"] = true,
		["default:dirt_with_grass"] = true,
	}

	minetest.register_globalstep(function(dtime)
		if math.random() > 0.05 then return end
		
		for _, grid in pairs(realistic_fluids.grids) do
			if grid.active then
				local sim = grid.sim
				for z = 1, BLOCK_SIZE - 2 do
					for x = 1, BLOCK_SIZE - 2 do
						local h = sim:get_water_height(x, z)
						if h > 0.1 then
							local ux, uz = sim:get_velocity(x, z)
							local speed_sq = ux*ux + uz*uz
							if speed_sq > 4.0 then -- high SWE velocity
								local idx = sim:get_index(x, z)
								local b = grid.base_y[idx]
								
								local adj = {{x=x+1, z=z}, {x=x-1, z=z}, {x=x, z=z+1}, {x=x, z=z-1}}
								for _, a in ipairs(adj) do
									local aidx = sim:get_index(a.x, a.z)
									local ab = grid.base_y[aidx]
									-- If neighbor terrain is at or slightly above water
									if ab and ab >= b and ab <= b + h + 1 then
										local wpos = {
											x = grid.block_pos.x + a.x,
											y = ab,
											z = grid.block_pos.z + a.z
										}
										local node = minetest.get_node(wpos)
										if erosible_nodes[node.name] then
											minetest.set_node(wpos, {name = "default:water_source"})
											-- Erode terrain level
											grid.base_y[aidx] = ab - 1
											sim:set_terrain(a.x, a.z, ab - 1)
											sim:add_water(a.x, a.z, 1.0)
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
