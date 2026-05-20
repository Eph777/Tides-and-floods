-- ca_water_node.lua
-- Custom water node that bypasses the C++ liquid engine entirely.
-- Uses paramtype2 = "leveled" for smooth visual height control (1-64 levels).

local MAX_VOL = realistic_fluids.settings.ca.max_volume  -- 64

-- ============================================================
-- Custom CA Water Node
-- ============================================================
-- liquidtype = "none" is the KEY: the engine's transformLiquids()
-- will never touch this node. All movement is handled by our
-- cellular automata in ca_fluid_sim.lua.

minetest.register_node("realistic_fluids:cwater", {
	description = "CA Water",
	drawtype = "nodebox",
	node_box = {
		type = "leveled",
		fixed = {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5},
	},

	tiles = {"default_water.png^[opacity:200"},
	special_tiles = {
		{name = "default_water.png^[opacity:200", backface_culling = false},
	},
	use_texture_alpha = "blend",

	paramtype = "light",
	paramtype2 = "leveled",
	leveled = MAX_VOL,

	-- CRITICAL: bypass the C++ liquid engine completely
	liquidtype = "none",
	liquid_alternative_flowing = "realistic_fluids:cwater",
	liquid_alternative_source = "realistic_fluids:cwater",

	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = true,
	is_ground_content = false,

	-- Player interaction
	drowning = 1,
	post_effect_color = {a = 120, r = 30, g = 60, b = 90},

	-- So other mods can detect this as water
	groups = {
		water = 1,
		cwater = 1,
		liquid = 1,
		not_in_creative_inventory = 1,
		not_blocking_trains = 1,
	},

	sounds = default and default.node_sound_water_defaults() or {},
	drop = "",

	-- Prevent the player from accidentally placing stuff in water
	on_blast = function() end,
})

-- ============================================================
-- LBM: Convert default:water_source near shore into CA nodes
-- ============================================================
-- Deep ocean stays as water_source (stable, no CA needed).
-- Shore zone (near sea_level) gets converted to cwater.

local ocean_settings = realistic_fluids.settings.ocean

minetest.register_lbm({
	name = "realistic_fluids:convert_shore_water",
	nodenames = {"default:water_source", "default:water_flowing"},
	run_at_every_load = true,
	action = function(pos, node)
		if not ocean_settings.enabled then return end

		local sea = ocean_settings.sea_level
		local deep = ocean_settings.deep_ocean_depth or 5

		-- Only convert water in the shore zone (above deep ocean threshold)
		-- Deep ocean (pos.y < sea - deep) stays as water_source
		if pos.y < sea - deep then return end

		-- Convert to CA water at full volume
		local vol = MAX_VOL
		if node.name == "default:water_flowing" then
			-- Flowing water: convert param2 level to our volume scale
			-- Engine param2: 0 = full, 7 = nearly empty
			local engine_level = node.param2 % 8  -- lower 3 bits
			vol = math.floor((1.0 - engine_level / 7.0) * MAX_VOL)
			vol = math.max(1, vol)
		end

		minetest.swap_node(pos, {name = "realistic_fluids:cwater", param2 = vol})
	end,
})

-- ============================================================
-- Utility functions for other modules
-- ============================================================

-- Get the water volume at a world position (works for both water types)
function realistic_fluids.get_water_volume(pos)
	local node = minetest.get_node(pos)
	if node.name == "realistic_fluids:cwater" then
		return node.param2
	elseif node.name == "default:water_source" then
		return MAX_VOL
	elseif node.name == "default:water_flowing" then
		local level = node.param2 % 8
		return math.floor((1.0 - level / 7.0) * MAX_VOL)
	end
	return 0
end

-- Get the water surface Y at a world position (fractional)
function realistic_fluids.get_water_surface_y(pos)
	local vol = realistic_fluids.get_water_volume(pos)
	if vol <= 0 then return nil end
	return pos.y - 0.5 + (vol / MAX_VOL)
end

minetest.log("action", "[realistic_fluids] CA water node registered (leveled, " .. MAX_VOL .. " levels).")
