-- swe_sim.lua
-- Shallow Water Equations (Pipe Model) for voxel fluid simulation

local SWESim = {}
SWESim.__index = SWESim

function SWESim.new(width, height)
	local self = setmetatable({}, SWESim)
	self.width = width
	self.height = height
	
	local num_cells = width * height
	
	-- 1D arrays for fast flat access: index = z * width + x + 1
	self.h = {} -- water depth
	self.b = {} -- bottom (terrain) height
	
	-- Fluxes out of the cell: 1=Right(+X), 2=Left(-X), 3=Top(+Z), 4=Bottom(-Z)
	self.f = {}
	self.f_new = {}
	
	for i = 1, num_cells do
		self.h[i] = 0.0
		self.b[i] = 0.0
		local base = (i-1)*4
		for d = 1, 4 do
			self.f[base + d] = 0.0
			self.f_new[base + d] = 0.0
		end
	end
	
	self.gravity = 9.8
	self.dt = 0.1
	self.damping = 0.99 -- Friction
	
	return self
end

function SWESim:get_index(x, z)
	if x < 0 or x >= self.width or z < 0 or z >= self.height then return nil end
	return z * self.width + x + 1
end

function SWESim:set_terrain(x, z, height)
	local idx = self:get_index(x, z)
	if idx then self.b[idx] = height end
end

function SWESim:add_water(x, z, amount)
	local idx = self:get_index(x, z)
	if idx then self.h[idx] = self.h[idx] + amount end
end

function SWESim:get_water_height(x, z)
	local idx = self:get_index(x, z)
	if idx then return self.h[idx] end
	return 0.0
end

function SWESim:get_velocity(x, z)
	local idx = self:get_index(x, z)
	if not idx then return 0.0, 0.0 end
	
	local h = self.h[idx]
	if h <= 0.001 then return 0.0, 0.0 end
	
	local base = (idx-1)*4
	-- Average flux through the cell
	-- Flux right (+X) is f[1], left (-X) is f[2], etc.
	-- If water flows in from left, neighbor's f[1] is entering us.
	-- We approximate velocity strictly by our own net outflow/inflow pressure.
	local vx = (self.f[base+1] - self.f[base+2]) / h
	local vz = (self.f[base+3] - self.f[base+4]) / h
	
	return vx, vz
end

-- Directions:
-- 1: dx=1, dz=0
-- 2: dx=-1, dz=0
-- 3: dx=0, dz=1
-- 4: dx=0, dz=-1
local dx = {1, -1, 0, 0}
local dz = {0, 0, 1, -1}
local opp = {2, 1, 4, 3}

function SWESim:step(wave_h)
	local w = self.width
	local h = self.height
	local dt = self.dt
	local g = self.gravity
	
	-- 1. Calculate Outfluxes
	for z = 0, h - 1 do
		for x = 0, w - 1 do
			local idx = z * w + x + 1
			local base = (idx-1)*4
			
			local H = self.h[idx] + self.b[idx]
			
			if self.h[idx] > 0 then
				local total_out = 0
				
				for d = 1, 4 do
					local nx = x + dx[d]
					local nz = z + dz[d]
					local nidx = self:get_index(nx, nz)
					
					local H_neighbor = 0
					if nidx then
						H_neighbor = self.h[nidx] + self.b[nidx]
					else
						-- Boundary condition: solid wall, H is very high
						H_neighbor = H + 100
					end
					
					-- Head difference
					local dH = H - H_neighbor
					
					-- Accelerate flux
					local new_f = self.f[base+d] + dt * g * dH
					new_f = new_f * self.damping
					
					if new_f < 0 then new_f = 0 end
					
					self.f_new[base+d] = new_f
					total_out = total_out + new_f
				end
				
				-- Scale fluxes if they exceed available volume
				local max_out = self.h[idx] / dt
				if total_out > max_out and total_out > 0 then
					local scale = max_out / total_out
					for d = 1, 4 do
						self.f_new[base+d] = self.f_new[base+d] * scale
					end
				end
			else
				for d = 1, 4 do
					self.f_new[base+d] = 0.0
				end
			end
		end
	end
	
	-- Swap fluxes
	self.f, self.f_new = self.f_new, self.f
	
	-- 2. Update Water Depth
	for z = 0, h - 1 do
		for x = 0, w - 1 do
			local idx = z * w + x + 1
			local base = (idx-1)*4
			
			local net_volume = 0
			
			-- Outflows
			net_volume = net_volume - self.f[base+1]
			net_volume = net_volume - self.f[base+2]
			net_volume = net_volume - self.f[base+3]
			net_volume = net_volume - self.f[base+4]
			
			-- Inflows from neighbors
			for d = 1, 4 do
				local nx = x + dx[d]
				local nz = z + dz[d]
				local nidx = self:get_index(nx, nz)
				if nidx then
					local nbase = (nidx-1)*4
					net_volume = net_volume + self.f[nbase + opp[d]]
				end
			end
			
			self.h[idx] = self.h[idx] + dt * net_volume
			if self.h[idx] < 0 then self.h[idx] = 0 end
			
			-- Boundary Wave Injection
			if wave_h and x == 0 then
				if self.h[idx] < wave_h then
					self.h[idx] = wave_h
				end
			end
		end
	end
end

return SWESim
