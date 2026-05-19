local FluidSim = dofile("fluid_sim.lua")
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
