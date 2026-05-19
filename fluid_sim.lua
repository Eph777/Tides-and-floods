-- fluid_sim.lua
-- Phase 1: Standalone LBM D2Q9 solver

local FluidSim = {}
FluidSim.__index = FluidSim

-- D2Q9 Lattice Constants
local NUM_DIRS = 9

-- Direction vectors (e_x, e_y)
local e_x = { 0, 1, 0, -1, 0, 1, -1, -1, 1 }
local e_y = { 0, 0, 1, 0, -1, 1, 1, -1, -1 }

-- Opposite directions for bounce-back
local op_dir = { 1, 4, 5, 2, 3, 8, 9, 6, 7 }

-- Weights (w_i)
local w = {
	4/9,   -- center
	1/9, 1/9, 1/9, 1/9, -- cardinal
	1/36, 1/36, 1/36, 1/36 -- diagonal
}

local cs2 = 1/3 -- Speed of sound squared
local inv_cs2 = 1 / cs2
local inv_2cs4 = 1 / (2 * cs2 * cs2)

function FluidSim.new(width, height, tau)
	local self = setmetatable({}, FluidSim)
	self.width = width
	self.height = height
	self.tau = tau or 0.6
	self.inv_tau = 1.0 / self.tau

	local num_cells = width * height

	-- 1D arrays for fast flat access: index = y * width + x (0-indexed logic mapped to Lua's 1-index)
	self.f = {}
	self.f_next = {}
	self.solid = {}

	for i = 1, num_cells * NUM_DIRS do
		self.f[i] = 0.0
		self.f_next[i] = 0.0
	end

	for i = 1, num_cells do
		self.solid[i] = false
		-- Initialize to equilibrium with rho=0, u=(0,0)
		for d = 1, NUM_DIRS do
			self.f[(i-1)*NUM_DIRS + d] = w[d] * 0.0 -- 0 density by default
		end
	end

	return self
end

function FluidSim:get_index(x, y)
	return y * self.width + x + 1
end

function FluidSim:set_solid(x, y, is_solid)
	if x < 0 or x >= self.width or y < 0 or y >= self.height then return end
	local idx = self:get_index(x, y)
	self.solid[idx] = is_solid
	
	-- Zero out distributions inside solids to avoid numerical issues
	if is_solid then
		local base = (idx - 1) * NUM_DIRS
		for d = 1, NUM_DIRS do
			self.f[base + d] = 0.0
		end
	end
end

function FluidSim:add_source(x, y, strength)
	if x < 0 or x >= self.width or y < 0 or y >= self.height then return end
	local idx = self:get_index(x, y)
	if self.solid[idx] then return end
	
	local base = (idx - 1) * NUM_DIRS
	for d = 1, NUM_DIRS do
		self.f[base + d] = self.f[base + d] + w[d] * strength
	end
end

function FluidSim:get_density(x, y)
	if x < 0 or x >= self.width or y < 0 or y >= self.height then return 0.0 end
	local idx = self:get_index(x, y)
	if self.solid[idx] then return 0.0 end
	
	local rho = 0.0
	local base = (idx - 1) * NUM_DIRS
	for d = 1, NUM_DIRS do
		rho = rho + self.f[base + d]
	end
	return rho
end

function FluidSim:get_velocity(x, y)
	if x < 0 or x >= self.width or y < 0 or y >= self.height then return 0.0, 0.0 end
	local idx = self:get_index(x, y)
	if self.solid[idx] then return 0.0, 0.0 end
	
	local rho = 0.0
	local ux = 0.0
	local uy = 0.0
	local base = (idx - 1) * NUM_DIRS
	
	for d = 1, NUM_DIRS do
		local f_val = self.f[base + d]
		rho = rho + f_val
		ux = ux + f_val * e_x[d]
		uy = uy + f_val * e_y[d]
	end
	
	if rho > 0.0001 then
		return ux / rho, uy / rho
	end
	return 0.0, 0.0
end

function FluidSim:step()
	-- 1. Collision (BGK) and 2. Streaming
	
	local w_i = self.width
	local h_i = self.height
	local f_old = self.f
	local f_new = self.f_next
	local inv_tau = self.inv_tau

	for y = 0, h_i - 1 do
		for x = 0, w_i - 1 do
			local idx = y * w_i + x + 1
			local base = (idx - 1) * NUM_DIRS
			
			if self.solid[idx] then
				-- Bounce-back happens during streaming into this cell
				for d = 1, NUM_DIRS do
					f_new[base + d] = 0.0
				end
			else
				-- Collision
				local rho = 0.0
				local ux = 0.0
				local uy = 0.0
				
				for d = 1, NUM_DIRS do
					local val = f_old[base + d]
					rho = rho + val
					ux = ux + val * e_x[d]
					uy = uy + val * e_y[d]
				end
				
				if rho > 0.0001 then
					ux = ux / rho
					uy = uy / rho
				else
					ux = 0.0
					uy = 0.0
				end
				
				local u_sq = ux*ux + uy*uy
				
				for d = 1, NUM_DIRS do
					local ex = e_x[d]
					local ey = e_y[d]
					local eu = ex*ux + ey*uy
					local feq = w[d] * rho * (1.0 + eu * inv_cs2 + (eu*eu) * inv_2cs4 - (u_sq * inv_cs2 * 0.5))
					
					-- Relax towards equilibrium
					f_old[base + d] = f_old[base + d] - inv_tau * (f_old[base + d] - feq)
				end
				
				-- Streaming
				for d = 1, NUM_DIRS do
					local nx = x + e_x[d]
					local ny = y + e_y[d]
					
					if nx >= 0 and nx < w_i and ny >= 0 and ny < h_i then
						local nidx = ny * w_i + nx + 1
						if self.solid[nidx] then
							-- Bounce back to current cell, opposite direction
							f_new[base + op_dir[d]] = f_old[base + d]
						else
							-- Stream to neighbor
							local nbase = (nidx - 1) * NUM_DIRS
							f_new[nbase + d] = f_old[base + d]
						end
					else
						-- Out of bounds - simple bounce back
						f_new[base + op_dir[d]] = f_old[base + d]
					end
				end
			end
		end
	end

	-- Swap arrays
	self.f, self.f_next = self.f_next, self.f
end

return FluidSim

-- ============================================================================
-- Test Harness
-- ============================================================================
if false then
	print("--- Running LBM Test Harness ---")
	
	local sim = FluidSim.new(10, 5, 0.8)
	
	-- Setup a channel with walls on top and bottom
	for x = 0, 9 do
		sim:set_solid(x, 0, true)
		sim:set_solid(x, 4, true)
	end
	
	-- Add a block in the middle
	sim:set_solid(4, 2, true)
	sim:set_solid(4, 3, true)
	sim:set_solid(4, 1, true)
	
	-- Add fluid on the left side
	for x = 1, 3 do
		for y = 1, 3 do
			sim:add_source(x, y, 1.0)
		end
	end
	
	print(string.format("Initial Density at (2,2): %.4f", sim:get_density(2, 2)))
	print(string.format("Initial Density at (7,2): %.4f", sim:get_density(7, 2)))
	
	-- Run simulation for some steps
	for i = 1, 50 do
		sim:step()
	end
	
	print(string.format("Density at (2,2) after 50 steps: %.4f", sim:get_density(2, 2)))
	print(string.format("Density at (7,2) after 50 steps: %.4f", sim:get_density(7, 2)))
	
	local vx, vy = sim:get_velocity(7, 2)
	print(string.format("Velocity at (7,2) after 50 steps: vx=%.4f, vy=%.4f", vx, vy))
	
	-- Print a simple ascii density map
	print("Density Map:")
	for y = 4, 0, -1 do
		local row = ""
		for x = 0, 9 do
			if sim.solid[sim:get_index(x,y)] then
				row = row .. "## "
			else
				local d = sim:get_density(x, y)
				if d < 0.05 then
					row = row .. " . "
				elseif d < 0.3 then
					row = row .. " ~ "
				else
					row = row .. string.format("%02.0f ", d*10)
				end
			end
		end
		print(row)
	end
	print("--------------------------------")
end
