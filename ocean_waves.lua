-- ocean_waves.lua
-- Gerstner Wave Math adapted for voxel ocean simulation
-- Inspired by the wave superposition technique used in the Minecraft Physics Mod's shader

local OceanWaves = {}

-- Wave constants (tuned for voxel-scale ocean)
local XZ_SCALE = 0.035
local TIME_MULT = 0.45
local BASE_FREQ = 6.0
local BASE_SPEED = 2.0
local WEIGHT_DECAY = 0.8
local FREQ_MULT = 1.18
local SPEED_MULT = 1.07
local ITER_INC = 12.0
local DRAG_MULT = 0.048

local math_sin = math.sin
local math_cos = math.cos
local math_exp = math.exp
local math_floor = math.floor

-- Compute the wave height offset at a given world (x, z) position and time.
-- Returns a Y offset (positive = above sea level, negative = below).
-- iterations: 1-5, more = finer detail but heavier CPU
-- amplitude: max wave height in blocks
function OceanWaves.get_height(x, z, time, iterations, amplitude)
	iterations = iterations or 3
	amplitude = amplitude or 1.8

	local px = x * XZ_SCALE
	local pz = z * XZ_SCALE

	local iter = 0.0
	local frequency = BASE_FREQ
	local speed = BASE_SPEED
	local weight = 1.0
	local height = 0.0
	local wave_sum = 0.0
	local mod_time = time * TIME_MULT

	for i = 1, iterations do
		local dir_x = math_sin(iter)
		local dir_z = math_cos(iter)

		-- Dot product of direction and position, scaled by frequency, plus time
		local phase = (dir_x * px + dir_z * pz) * frequency + mod_time * speed

		-- Sharp crest function: exp(sin(x) - 1) produces pointed peaks
		local wave = math_exp(math_sin(phase) - 1.0)
		local result = wave * math_cos(phase)

		-- Drag: warp position for more organic look
		local force_x = result * weight * dir_x
		local force_z = result * weight * dir_z
		px = px - force_x * DRAG_MULT
		pz = pz - force_z * DRAG_MULT

		height = height + wave * weight
		wave_sum = wave_sum + weight

		-- Cascade to next octave
		iter = iter + ITER_INC
		weight = weight * WEIGHT_DECAY
		frequency = frequency * FREQ_MULT
		speed = speed * SPEED_MULT
	end

	if wave_sum == 0 then return 0 end

	-- Normalize and scale: center around 0 (crests positive, troughs negative)
	return (height / wave_sum) * amplitude - amplitude * 0.5
end

-- Compute approximate flow velocity at (x, z) by finite differences.
-- Returns vx, vz (horizontal velocity components).
function OceanWaves.get_velocity(x, z, time, iterations, amplitude)
	local delta = 0.5
	local h_center = OceanWaves.get_height(x, z, time, iterations, amplitude)
	local h_right = OceanWaves.get_height(x + delta, z, time, iterations, amplitude)
	local h_front = OceanWaves.get_height(x, z + delta, time, iterations, amplitude)

	-- Gradient gives the slope; water flows downhill
	local vx = -(h_right - h_center) / delta * 2.0
	local vz = -(h_front - h_center) / delta * 2.0

	return vx, vz
end

-- Get the integer surface Y level and fractional remainder for block placement.
-- sea_level: the base Y of the ocean surface (e.g. 1)
-- Returns: top_y (integer block Y), remainder (0.0-1.0 fractional part)
function OceanWaves.get_surface(x, z, time, sea_level, iterations, amplitude)
	local offset = OceanWaves.get_height(x, z, time, iterations, amplitude)
	local surface = sea_level + offset
	local top_y = math_floor(surface)
	local remainder = surface - top_y
	return top_y, remainder
end

return OceanWaves
