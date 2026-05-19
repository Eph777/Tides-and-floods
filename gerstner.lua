-- gerstner.lua
-- Translated from Minecraft Physics Mod's ocean.glsl shader

local Gerstner = {}

-- Shader Constants
local PHYSICS_XZ_SCALE = 0.035
local PHYSICS_TIME_MULTIPLICATOR = 0.45
local PHYSICS_FREQUENCY = 6.0
local PHYSICS_SPEED = 2.0
local PHYSICS_WEIGHT = 0.8
local PHYSICS_FREQUENCY_MULT = 1.18
local PHYSICS_SPEED_MULT = 1.07
local PHYSICS_ITER_INC = 12.0
local PHYSICS_DRAG_MULT = 0.048

local WAVE_HEIGHT_AMP = 3.0 -- Max amplitude
local WAVE_HORIZONTAL_SCALE = 1.0

-- Returns the absolute surface height (Y offset) of the wave at (x, z) at the given time
function Gerstner.get_height(x, z, time, iterations)
	iterations = iterations or 3
	local factor = 1.0
	local adjustedFactor = 1.0 -- clamp(factor * 2.0, 0.1, 1.0)
	
	local px = x * PHYSICS_XZ_SCALE * WAVE_HORIZONTAL_SCALE
	local pz = z * PHYSICS_XZ_SCALE * WAVE_HORIZONTAL_SCALE
	
	local iter = 0.0
	local frequency = PHYSICS_FREQUENCY
	local speed = PHYSICS_SPEED
	local weight = 1.0
	local height = 0.0
	local waveSum = 0.0
	local modifiedTime = time * PHYSICS_TIME_MULTIPLICATOR
	
	for i = 1, iterations do
		local dir_x = math.sin(iter)
		local dir_z = math.cos(iter)
		
		local dot_x = (dir_x * px + dir_z * pz) * frequency + modifiedTime * speed
		
		local wave = math.exp(math.sin(dot_x) - 1.0)
		local result = wave * math.cos(dot_x)
		local force_x = result * weight * dir_x
		local force_z = result * weight * dir_z
		
		px = px - force_x * PHYSICS_DRAG_MULT * adjustedFactor
		pz = pz - force_z * PHYSICS_DRAG_MULT * adjustedFactor
		
		height = height + wave * weight
		iter = iter + PHYSICS_ITER_INC
		waveSum = waveSum + weight
		weight = weight * PHYSICS_WEIGHT
		frequency = frequency * PHYSICS_FREQUENCY_MULT
		speed = speed * PHYSICS_SPEED_MULT
	end
	
	if waveSum == 0 then return 0 end
	
	return (height / waveSum) * WAVE_HEIGHT_AMP * factor - WAVE_HEIGHT_AMP * factor * 0.5
end

return Gerstner
