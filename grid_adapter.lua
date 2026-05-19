-- grid_adapter.lua
-- Phase 2: Voxel Grid Adapter

local FluidSim = dofile(minetest.get_modpath("realistic_fluids") .. "/fluid_sim.lua")
local settings = realistic_fluids.settings

realistic_fluids.grids = {}
realistic_fluids.active_cells = 0

local BLOCK_SIZE = 16

-- Nodes
local WATER_FLOWING = "realistic_fluids:water_flowing_7" -- Default flowing node we will replace with animated ones later
local WATER_SOURCE = "default:water_source"
local AIR = "air"

-- Storage for cross-chunk borders (not fully implemented in MVP, but prepped)
local mod_storage = minetest.get_mod_storage()

local FluidGrid = {}
FluidGrid.__index = FluidGrid

function FluidGrid.new(block_pos)
	local self = setmetatable({}, FluidGrid)
	self.block_pos = block_pos
	
	-- We maintain one 16x16 2D LBM sim per Y-level (16 levels in a MapBlock)
	self.y_sims = {}
	self.active = true
	self.needs_save = false
	
	return self
end

-- Initialize the grid from the actual world nodes
function FluidGrid:init_from_world()
	local min_pos = self.block_pos
	local max_pos = vector.add(min_pos, {x=BLOCK_SIZE-1, y=BLOCK_SIZE-1, z=BLOCK_SIZE-1})
	
	-- Read chunk data (LVM is faster than get_node in a loop)
	local vm = minetest.get_voxel_manip()
	local emin, emax = vm:read_from_map(min_pos, max_pos)
	local data = vm:get_data()
	local param2_data = vm:get_param2_data()
	local va = VoxelArea:new{MinEdge=emin, MaxEdge=emax}
	
	local c_water_source = minetest.get_content_id("default:water_source")
	local c_water_flowing = minetest.get_content_id("default:water_flowing")
	local c_air = minetest.get_content_id("air")
	local c_ignore = minetest.get_content_id("ignore")
	
	for y = 0, BLOCK_SIZE - 1 do
		local has_fluid = false
		local sim = FluidSim.new(BLOCK_SIZE, BLOCK_SIZE, settings.lbm_tau)
		
		for z = 0, BLOCK_SIZE - 1 do
			for x = 0, BLOCK_SIZE - 1 do
				local vi = va:index(min_pos.x + x, min_pos.y + y, min_pos.z + z)
				local cid = data[vi]
				local p2 = param2_data[vi]
				
				if cid == c_water_source then
					sim:add_source(x, z, 7.0) -- Max density
					has_fluid = true
				elseif cid == c_water_flowing then
					-- Extract liquid level from param2 (0-7)
					local level = math.max(1, p2 % 8)
					sim:add_source(x, z, level)
					has_fluid = true
				elseif cid ~= c_air and cid ~= c_ignore then
					-- Treat as solid boundary
					sim:set_solid(x, z, true)
				end
			end
		end
		
		if has_fluid then
			self.y_sims[y] = sim
		end
	end
end

-- Synchronize LBM state with the Luanti world
function FluidGrid:sync(wave_fx, wave_fz)
	if not self.active then return end
	
	local nodes_to_set = {}
	local min_pos = self.block_pos
	
	-- 1. Vertical Flow (Gravity & Pressure)
	-- Simple approximation: move density downwards if cell below is empty/non-solid
	for y = 1, BLOCK_SIZE - 1 do
		local sim_upper = self.y_sims[y]
		if sim_upper then
			local sim_lower = self.y_sims[y-1]
			if not sim_lower then
				sim_lower = FluidSim.new(BLOCK_SIZE, BLOCK_SIZE, settings.lbm_tau)
				self.y_sims[y-1] = sim_lower
				-- Read solids for the new lower sim
				self:fetch_solids(y-1)
			end
			
			for z = 0, BLOCK_SIZE - 1 do
				for x = 0, BLOCK_SIZE - 1 do
					local upper_idx = sim_upper:get_index(x, z)
					local lower_idx = sim_lower:get_index(x, z)
					
					if not sim_upper.solid[upper_idx] and not sim_lower.solid[lower_idx] then
						local rho_upper = sim_upper:get_density(x, z)
						if rho_upper > 0.1 then
							local rho_lower = sim_lower:get_density(x, z)
							-- Move density down
							local transfer = math.min(rho_upper, 7.0 - rho_lower)
							if transfer > 0 then
								-- Subtract from upper, add to lower (approximate by modifying f directly)
								-- A proper LBM would bounce vertically, but this is a 2.5D approximation
								local base_up = (upper_idx - 1) * 9
								local base_down = (lower_idx - 1) * 9
								
								local ratio = (rho_upper - transfer) / rho_upper
								for d = 1, 9 do
									local amount = sim_upper.f[base_up + d] * (1.0 - ratio)
									sim_upper.f[base_up + d] = sim_upper.f[base_up + d] - amount
									sim_lower.f[base_down + d] = sim_lower.f[base_down + d] + amount
								end
							end
						end
					end
				end
			end
		end
	end
	
	-- 2. Horizontal Flow (LBM Step)
	local active_layers = 0
	for y = 0, BLOCK_SIZE - 1 do
		local sim = self.y_sims[y]
		if sim then
			active_layers = active_layers + 1
			if realistic_fluids.active_cells + (BLOCK_SIZE * BLOCK_SIZE) <= settings.tick_budget then
				if wave_fx and wave_fz then
					sim.force_x = wave_fx
					sim.force_y = wave_fz
				end
				sim:step()
				realistic_fluids.active_cells = realistic_fluids.active_cells + (BLOCK_SIZE * BLOCK_SIZE)
				
				-- Translate to node updates
				for z = 0, BLOCK_SIZE - 1 do
					for x = 0, BLOCK_SIZE - 1 do
						local idx = sim:get_index(x, z)
						if not sim.solid[idx] then
							local rho = sim:get_density(x, z)
							local pos = {x = min_pos.x + x, y = min_pos.y + y, z = min_pos.z + z}
							
							if rho > 0.5 then
								local level = math.min(7, math.floor(rho))
								-- We use water_flowing_N in Phase 4, for now use default:water_flowing
								-- We construct the param2 value for flowing liquid
								table.insert(nodes_to_set, {
									pos = pos,
									node = {name = "default:water_flowing", param2 = level}
								})
							else
								-- Air
								table.insert(nodes_to_set, {
									pos = pos,
									node = {name = "air"}
								})
							end
						end
					end
				end
			end
		end
	end
	
	if active_layers == 0 then
		self.active = false
	end
	
	-- 3. Apply Node Changes via bulk_set_node
	if #nodes_to_set > 0 then
		minetest.bulk_set_node(nodes_to_set)
	end
end

function FluidGrid:fetch_solids(y)
	local sim = self.y_sims[y]
	if not sim then return end
	
	local min_pos = self.block_pos
	local y_pos = min_pos.y + y
	
	local p1 = {x = min_pos.x, y = y_pos, z = min_pos.z}
	local p2 = {x = min_pos.x + BLOCK_SIZE - 1, y = y_pos, z = min_pos.z + BLOCK_SIZE - 1}
	
	local vm = minetest.get_voxel_manip()
	local emin, emax = vm:read_from_map(p1, p2)
	local data = vm:get_data()
	local va = VoxelArea:new{MinEdge=emin, MaxEdge=emax}
	
	local c_water_source = minetest.get_content_id("default:water_source")
	local c_water_flowing = minetest.get_content_id("default:water_flowing")
	local c_air = minetest.get_content_id("air")
	local c_ignore = minetest.get_content_id("ignore")
	
	for z = 0, BLOCK_SIZE - 1 do
		for x = 0, BLOCK_SIZE - 1 do
			local vi = va:index(min_pos.x + x, y_pos, min_pos.z + z)
			local cid = data[vi]
			if cid ~= c_air and cid ~= c_ignore and cid ~= c_water_source and cid ~= c_water_flowing then
				sim:set_solid(x, z, true)
			end
		end
	end
end

-- Global Manager
local global_wave_time = 0
minetest.register_globalstep(function(dtime)
	if settings.disable_lbm then return end
	
	global_wave_time = global_wave_time + dtime
	local wave_fx, wave_fz = 0, 0
	if settings.enable_waves then
		-- Strong, pulsing directional storm wind to create crashing waves
		-- A constant base push + large periodic pulses
		local pulse = math.max(0, math.sin(global_wave_time * 1.5)) * 4.0
		wave_fx = (1.0 + pulse) * settings.wave_force
		wave_fz = (math.cos(global_wave_time * 0.5) * settings.wave_force)
	end
	
	realistic_fluids.active_cells = 0
	for _, grid in pairs(realistic_fluids.grids) do
		grid:sync(wave_fx, wave_fz)
		if realistic_fluids.active_cells >= settings.tick_budget then
			break -- Yield tick budget to engine
		end
	end
end)

-- Manage Grid Loading/Unloading
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

-- Detect water placement or updates to trigger LBM
minetest.register_on_placenode(function(pos, newnode, placer, oldnode, itemstack, pointed_thing)
	if settings.disable_lbm then return end
	if minetest.get_item_group(newnode.name, "water") > 0 then
		local bpos = get_block_pos(pos)
		local hash = hash_pos(bpos)
		
		if not realistic_fluids.grids[hash] then
			local grid = FluidGrid.new(bpos)
			grid:init_from_world()
			realistic_fluids.grids[hash] = grid
		end
		
		local grid = realistic_fluids.grids[hash]
		grid.active = true
		
		-- Inject density at specific cell
		local ly = pos.y - bpos.y
		local lx = pos.x - bpos.x
		local lz = pos.z - bpos.z
		
		if not grid.y_sims[ly] then
			grid.y_sims[ly] = FluidSim.new(BLOCK_SIZE, BLOCK_SIZE, settings.lbm_tau)
			grid:fetch_solids(ly)
		end
		grid.y_sims[ly]:add_source(lx, lz, 7.0)
	end
end)

return FluidGrid
