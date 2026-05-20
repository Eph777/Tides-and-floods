-- init.lua
-- Physics Mod for Luanti
-- Adapted from Minecraft Physics Mod mechanics

local modpath = minetest.get_modpath("realistic_fluids")

-- Phase 0: Settings (creates the realistic_fluids global table)
dofile(modpath .. "/settings.lua")

-- Global Force Manager for tide/wind-driven surge
realistic_fluids.force = {
	x = 1, -- push x (1, -1, 0)
	z = 0, -- push z (1, -1, 0)
	strength = 0.0,
}

-- Register custom nodes
dofile(modpath .. "/nodes.lua")

-- Update global tide force over a 4-minute period
minetest.register_globalstep(function(dtime)
	if realistic_fluids.settings.disabled then return end
	
	realistic_fluids.ocean_time = (realistic_fluids.ocean_time or 0) + dtime
	
	local period = 240 -- 4-minute tide cycle
	local angle = (realistic_fluids.ocean_time / period) * 2 * math.pi
	local force_val = math.sin(angle)
	
	if force_val > 0.1 then
		realistic_fluids.force.x = 1
		realistic_fluids.force.strength = (force_val - 0.1) / 0.9
	elseif force_val < -0.1 then
		realistic_fluids.force.x = -1
		realistic_fluids.force.strength = math.abs(force_val + 0.1) / 0.9
	else
		realistic_fluids.force.x = 0
		realistic_fluids.force.strength = 0.0
	end
end)

if realistic_fluids.settings.disabled then
	minetest.log("action", "[realistic_fluids] Mod disabled via settings.")
	return
end

-- Phase 1: Ocean Physics
if realistic_fluids.settings.ocean.enabled then
	realistic_fluids.ocean_waves = dofile(modpath .. "/ocean_waves.lua")
	realistic_fluids.ocean_time = 0
	dofile(modpath .. "/ocean_manager.lua")  -- Chunk management + VoxelManip updates
	dofile(modpath .. "/ocean_buoyancy.lua") -- Entity bobbing + splash effects
end

-- Phase 2: Building Debris
if realistic_fluids.settings.debris.enabled then
	dofile(modpath .. "/debris_fragments.lua")  -- Debris entity definition
	dofile(modpath .. "/debris_hooks.lua")      -- Break/blast event hooks
end

minetest.log("action", "[realistic_fluids] Physics Mod loaded successfully.")
