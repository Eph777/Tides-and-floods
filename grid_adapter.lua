-- grid_adapter.lua
-- Phase 2: Voxel Grid Adapter (SWE Heightfield)

local SWESim = dofile(minetest.get_modpath("realistic_fluids") .. "/swe_sim.lua")
local settings = realistic_fluids.settings

realistic_fluids.grids = {}
realistic_fluids.active_cells = 0

local BLOCK_SIZE = 16

-- We maintain 2D grid chunks
local FluidGrid = {}
FluidGrid.__index = FluidGrid

function FluidGrid.new(block_pos)
	local self = setmetatable({}, FluidGrid)
	-- block_pos is the minimum (X, Z) coordinate of this 16x16 column
	self.block_pos = {x = block_pos.x, y = 0, z = block_pos.z}
	
	self.sim = SWESim.new(BLOCK_SIZE, BLOCK_SIZE)
	self.active = true
	self.base_y = {} -- tracks the terrain base Y level for each (X, Z) column
	
	return self
end

function FluidGrid:init_from_world()
	local min_x = self.block_pos.x
	local min_z = self.block_pos.z
	
	-- We scan the world column to find the water surface and terrain base
	-- In a full engine, we'd use lvm over a large vertical slice.
	-- For simplicity in this adapter, we will assume a fixed vertical range for oceans (e.g. y = -16 to 16)
	local y_min = -16
	local y_max = 32
	
	local p1 = {x = min_x, y = y_min, z = min_z}
	local p2 = {x = min_x + BLOCK_SIZE - 1, y = y_max, z = min_z + BLOCK_SIZE - 1}
	
	local vm = minetest.get_voxel_manip()
	local emin, emax = vm:read_from_map(p1, p2)
	local data = vm:get_data()
	local param2_data = vm:get_param2_data()
	local va = VoxelArea:new{MinEdge=emin, MaxEdge=emax}
	
	local c_water_source = minetest.get_content_id("default:water_source")
	local c_water_flowing = minetest.get_content_id("default:water_flowing")
	local c_air = minetest.get_content_id("air")
	local c_ignore = minetest.get_content_id("ignore")
	
	for z = 0, BLOCK_SIZE - 1 do
		for x = 0, BLOCK_SIZE - 1 do
			local idx = self.sim:get_index(x, z)
			
			-- Find highest water and terrain
			local water_top = -999
			local terrain_top = -999
			local total_water = 0
			
			for y = y_max, y_min, -1 do
				local vi = va:index(min_x + x, y, min_z + z)
				local cid = data[vi]
				
				if cid == c_water_source then
					if water_top == -999 then water_top = y end
					total_water = total_water + 1.0
				elseif cid == c_water_flowing then
					if water_top == -999 then water_top = y end
					local level = math.max(1, param2_data[vi] % 8) / 8.0
					total_water = total_water + level
				elseif cid ~= c_air and cid ~= c_ignore and terrain_top == -999 then
					-- Ignore blocks above water, or if no water, ignore high terrain (bridges/canopies)
					if (water_top ~= -999 and y < water_top) or (water_top == -999 and y <= 4) then
						local name = minetest.get_name_from_content_id(cid)
						local def = minetest.registered_nodes[name]
						if def and def.walkable and not (def.groups and (def.groups.leaves or def.groups.tree)) then
							terrain_top = y
						end
					end
				end
			end
			
			if terrain_top == -999 then terrain_top = y_min end
			
			self.base_y[idx] = terrain_top
			self.sim:set_terrain(x, z, terrain_top)
			
			if total_water > 0 then
				self.sim:add_water(x, z, total_water)
			end
		end
	end
end

function FluidGrid:sync(wave_h)
	if not self.active then return end
	
	local air_pos = {}
	local source_pos = {}
	local flowing_pos = {}
	for i = 1, 7 do flowing_pos[i] = {} end
	local min_x = self.block_pos.x
	local min_z = self.block_pos.z
	
	if realistic_fluids.active_cells + (BLOCK_SIZE * BLOCK_SIZE) <= settings.tick_budget then
		self.sim:step(wave_h)
		realistic_fluids.active_cells = realistic_fluids.active_cells + (BLOCK_SIZE * BLOCK_SIZE)
		
		local has_water = false
		
		for z = 0, BLOCK_SIZE - 1 do
			for x = 0, BLOCK_SIZE - 1 do
				local idx = self.sim:get_index(x, z)
				local h = self.sim:get_water_height(x, z)
				local b = self.base_y[idx]
				
				if h > 0.05 then
					has_water = true
					local target_top = b + h
					local top_y = math.floor(target_top)
					local remainder = target_top - top_y
					
					-- Clear air blocks above the wave
					for y = top_y + 1, top_y + 3 do
						local pos = {x = min_x + x, y = y, z = min_z + z}
						table.insert(air_pos, {x = min_x + x, y = y, z = min_z + z})
					end
					
					-- Set water blocks
					for y = b + 1, top_y do
						local pos = {x = min_x + x, y = y, z = min_z + z}
						table.insert(source_pos, {x = min_x + x, y = y, z = min_z + z})
					end
					
					-- Set surface flowing block
					if remainder > 0.1 then
						local level = math.floor(remainder * 8)
						level = math.min(7, math.max(1, level))
						local pos = {x = min_x + x, y = top_y + 1, z = min_z + z}
						table.insert(flowing_pos[level], {x = min_x + x, y = top_y + 1, z = min_z + z})
					end
				else
					-- Clean up if it was wet
					for y = b + 1, b + 3 do
						local pos = {x = min_x + x, y = y, z = min_z + z}
						table.insert(air_pos, {x = min_x + x, y = y, z = min_z + z})
					end
				end
			end
		end
		
		if not has_water then
			self.active = false
		end
	end
	
	for _, p in ipairs(air_pos) do minetest.swap_node(p, {name="air"}) end
	for _, p in ipairs(source_pos) do minetest.swap_node(p, {name="default:water_source"}) end
	for lvl = 1, 7 do
		for _, p in ipairs(flowing_pos[lvl]) do
			minetest.swap_node(p, {name="realistic_fluids:water_flowing_" .. lvl})
		end
	end
end

-- Global Manager with Round-Robin Update
local global_wave_time = 0
local last_hash = nil

minetest.register_globalstep(function(dtime)
	if settings.disable_lbm then return end
	
	global_wave_time = global_wave_time + dtime
	local wave_h = nil
	if settings.enable_waves then
		-- Boundary wave generator: injects a 1.5-block high rolling wave
		wave_h = math.max(0, math.sin(global_wave_time * 1.5)) * 1.5 * settings.wave_force
	end
	
	realistic_fluids.active_cells = 0
	
	local start_hash = last_hash
	local hash, grid = next(realistic_fluids.grids, last_hash)
	if not hash then hash, grid = next(realistic_fluids.grids) end
	
	while hash do
		if grid.active then
			grid:sync(wave_h)
		end
		
		last_hash = hash
		if realistic_fluids.active_cells >= settings.tick_budget then
			break
		end
		
		hash, grid = next(realistic_fluids.grids, hash)
		if hash == start_hash then break end
	end
end)

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
		
		local lx = pos.x - bpos.x
		local lz = pos.z - bpos.z
		grid.sim:add_water(lx, lz, 1.0)
	end
end)

minetest.register_lbm({
	name = "realistic_fluids:wake_water",
	nodenames = {"group:water"},
	run_at_every_load = true,
	action = function(pos, node)
		if settings.disable_lbm then return end
		local bpos = get_block_pos(pos)
		local hash = hash_pos(bpos)
		
		if not realistic_fluids.grids[hash] then
			local grid = FluidGrid.new(bpos)
			grid:init_from_world()
			realistic_fluids.grids[hash] = grid
		end
		realistic_fluids.grids[hash].active = true
	end
})

return FluidGrid
