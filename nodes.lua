-- nodes.lua
-- Custom water node definitions for realistic_fluids tide and wave system

local debug_colors = realistic_fluids.settings.ocean.debug_colors

-- Helper to colorize texture strings if debug mode is active
local function get_texture(base, color)
	if debug_colors and color then
		return base .. "^[colorize:" .. color
	end
	return base
end

-- Active waves propagation queue
realistic_fluids.active_waves = {}

function realistic_fluids.queue_wave(pos)
	local hash = minetest.hash_node_position(pos)
	realistic_fluids.active_waves[hash] = {x = pos.x, y = pos.y, z = pos.z}
end

-- ============================================================
-- SEAWATER
-- ============================================================
minetest.register_node("realistic_fluids:seawater", {
	description = "Seawater (Still)",
	drawtype = "liquid",
	waving = 3,
	tiles = {
		{
			name = "default_water_source_animated.png",
			backface_culling = false,
			animation = {
				type = "vertical_frames",
				aspect_w = 16,
				aspect_h = 16,
				length = 2.0,
			},
		},
		{
			name = "default_water_source_animated.png",
			backface_culling = false,
			animation = {
				type = "vertical_frames",
				aspect_w = 16,
				aspect_h = 16,
				length = 2.0,
			},
		},
	},
	use_texture_alpha = "blend",
	paramtype = "light",
	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = true,
	is_ground_content = false,
	drop = "",
	drowning = 1,
	liquid_viscosity = 1,
	liquid_move_physics = true,
	liquidtype = "source",
	liquid_range = 3,
	liquid_alternative_flowing = "realistic_fluids:wave",
	liquid_alternative_source = "realistic_fluids:seawater",
	liquid_renewable = true,
	floodable = false,
	post_effect_color = {a = 103, r = 30, g = 30, b = 90},
	groups = {water = 3, liquid = 3, cools_lava = 1},
})

-- ============================================================
-- WAVE
-- ============================================================
minetest.register_node("realistic_fluids:wave", {
	description = "Ocean Wave (Flowing)",
	drawtype = "flowingliquid",
	waving = 3,
	tiles = {"default_water.png"},
	special_tiles = {
		{
			name = get_texture("default_water_flowing_animated.png", "#99f:100"),
			backface_culling = false,
			animation = {
				type = "vertical_frames",
				aspect_w = 16,
				aspect_h = 16,
				length = 0.5,
			},
		},
		{
			name = get_texture("default_water_flowing_animated.png", "#99f:100"),
			backface_culling = false,
			animation = {
				type = "vertical_frames",
				aspect_w = 16,
				aspect_h = 16,
				length = 0.5,
			},
		},
	},
	use_texture_alpha = "blend",
	paramtype = "light",
	paramtype2 = "flowingliquid",
	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = true,
	is_ground_content = false,
	drop = "",
	drowning = 1,
	liquid_viscosity = 1,
	liquid_move_physics = true,
	liquidtype = "flowing",
	liquid_alternative_flowing = "realistic_fluids:wave",
	liquid_alternative_source = "realistic_fluids:seawater",
	liquid_renewable = false,
	floodable = true,
	post_effect_color = {a = 103, r = 30, g = 60, b = 90},
	groups = {water = 3, liquid = 3, not_in_creative_inventory = 0, cools_lava = 1},
	on_construct = function(pos)
		realistic_fluids.queue_wave(pos)
	end,
})

-- ============================================================
-- SHOREWATER
-- ============================================================
minetest.register_node("realistic_fluids:shorewater", {
	description = "Shorewater (Tide Receder)",
	drawtype = "liquid",
	waving = 3,
	tiles = {
		{
			name = get_texture("default_water_source_animated.png", "#fff:100"),
			backface_culling = false,
			animation = {
				type = "vertical_frames",
				aspect_w = 16,
				aspect_h = 16,
				length = 2.0,
			},
		},
		{
			name = get_texture("default_water_source_animated.png", "#fff:100"),
			backface_culling = false,
			animation = {
				type = "vertical_frames",
				aspect_w = 16,
				aspect_h = 16,
				length = 2.0,
			},
		},
	},
	use_texture_alpha = "blend",
	paramtype = "light",
	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = true,
	is_ground_content = false,
	drop = "",
	drowning = 1,
	liquid_viscosity = 1,
	liquid_move_physics = true,
	liquidtype = "source",
	liquid_range = 0,
	liquid_alternative_flowing = "realistic_fluids:wave_shorewater",
	liquid_alternative_source = "realistic_fluids:shorewater",
	liquid_renewable = false,
	floodable = false,
	post_effect_color = {a = 103, r = 30, g = 30, b = 90},
	groups = {water = 3, liquid = 3, cools_lava = 1},
})

-- ============================================================
-- OFFSHORE_WATER
-- ============================================================
minetest.register_node("realistic_fluids:offshore_water", {
	description = "Offshore Water (Tide Riser)",
	drawtype = "liquid",
	waving = 3,
	tiles = {
		{
			name = get_texture("default_water_source_animated.png", "#000:100"),
			backface_culling = false,
			animation = {
				type = "vertical_frames",
				aspect_w = 16,
				aspect_h = 16,
				length = 2.0,
			},
		},
		{
			name = get_texture("default_water_source_animated.png", "#000:100"),
			backface_culling = false,
			animation = {
				type = "vertical_frames",
				aspect_w = 16,
				aspect_h = 16,
				length = 2.0,
			},
		},
	},
	use_texture_alpha = "blend",
	paramtype = "light",
	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = true,
	is_ground_content = false,
	drop = "",
	drowning = 1,
	liquid_viscosity = 1,
	liquid_move_physics = true,
	liquidtype = "source",
	liquid_range = 0,
	liquid_alternative_flowing = "realistic_fluids:wave_offshorewater",
	liquid_alternative_source = "realistic_fluids:offshore_water",
	liquid_renewable = false,
	floodable = false,
	post_effect_color = {a = 103, r = 30, g = 30, b = 90},
	groups = {water = 3, liquid = 3, cools_lava = 1},
})

-- ============================================================
-- Helper Wave Nodes (To allow correct source type mechanics)
-- ============================================================
minetest.register_node("realistic_fluids:wave_shorewater", {
	description = "Shore Wave helper",
	drawtype = "flowingliquid",
	waving = 3,
	tiles = {"default_water.png"},
	special_tiles = {
		{
			name = get_texture("default_water_flowing_animated.png", "#99f:100"),
			backface_culling = false,
			animation = {
				type = "vertical_frames",
				aspect_w = 16,
				aspect_h = 16,
				length = 0.5,
			},
		},
		{
			name = get_texture("default_water_flowing_animated.png", "#99f:100"),
			backface_culling = false,
			animation = {
				type = "vertical_frames",
				aspect_w = 16,
				aspect_h = 16,
				length = 0.5,
			},
		},
	},
	use_texture_alpha = "blend",
	paramtype = "light",
	paramtype2 = "flowingliquid",
	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = true,
	is_ground_content = false,
	drop = "",
	drowning = 1,
	liquid_viscosity = 1,
	liquid_move_physics = true,
	liquidtype = "flowing",
	liquid_range = 0,
	liquid_alternative_flowing = "realistic_fluids:wave_shorewater",
	liquid_alternative_source = "realistic_fluids:shorewater",
	liquid_renewable = false,
	floodable = true,
	post_effect_color = {a = 103, r = 30, g = 60, b = 90},
	groups = {water = 3, liquid = 3, not_in_creative_inventory = 1, cools_lava = 1},
})

minetest.register_node("realistic_fluids:wave_offshorewater", {
	description = "Offshore Wave helper",
	drawtype = "flowingliquid",
	waving = 3,
	tiles = {"default_water.png"},
	special_tiles = {
		{
			name = get_texture("default_water_flowing_animated.png", "#99f:100"),
			backface_culling = false,
			animation = {
				type = "vertical_frames",
				aspect_w = 16,
				aspect_h = 16,
				length = 0.5,
			},
		},
		{
			name = get_texture("default_water_flowing_animated.png", "#99f:100"),
			backface_culling = false,
			animation = {
				type = "vertical_frames",
				aspect_w = 16,
				aspect_h = 16,
				length = 0.5,
			},
		},
	},
	use_texture_alpha = "blend",
	paramtype = "light",
	paramtype2 = "flowingliquid",
	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = true,
	is_ground_content = false,
	drop = "",
	drowning = 1,
	liquid_viscosity = 1,
	liquid_move_physics = true,
	liquidtype = "flowing",
	liquid_range = 0,
	liquid_alternative_flowing = "realistic_fluids:wave_offshorewater",
	liquid_alternative_source = "realistic_fluids:offshore_water",
	liquid_renewable = false,
	floodable = true,
	post_effect_color = {a = 103, r = 30, g = 60, b = 90},
	groups = {water = 3, liquid = 3, not_in_creative_inventory = 1, cools_lava = 1},
})

-- ============================================================
-- Backward compatibility aliases for tides namespace
-- ============================================================
minetest.register_alias("tides:seawater", "realistic_fluids:seawater")
minetest.register_alias("tides:wave", "realistic_fluids:wave")
minetest.register_alias("tides:shorewater", "realistic_fluids:shorewater")
minetest.register_alias("tides:offshore_water", "realistic_fluids:offshore_water")
minetest.register_alias("tides:wave_shorewater", "realistic_fluids:wave_shorewater")
minetest.register_alias("tides:wave_offshorewater", "realistic_fluids:wave_offshorewater")

-- ============================================================
-- Flooding behavior checker
-- ============================================================
realistic_fluids.can_it_flood = function(node)
	-- To avoid feedback loops
	if node == "realistic_fluids:wave" or node == "tides:wave" then
		return false
	end

	local def = minetest.registered_nodes[node] or {}
	local drawtype = def.drawtype

	local function part_of_any_group(itemname, ...)
		local groups = def.groups or {}
		for _, v in ipairs({...}) do
			if groups[v] and groups[v] > 0 then
				return true
			end
		end
		return false
	end

	if drawtype == "airlike"
		or drawtype == "flowingliquid"
		or def.floodable
		or (drawtype == "plantlike"
			and part_of_any_group(node, "flora", "grass", "flowers", "saplings", "float", "mushroom")
			)
	then
		return true
	else
		return false
	end
end

-- ============================================================
-- Waterlily Floating group overrides
-- ============================================================
if minetest.get_modpath("flowers") ~= nil then
	minetest.override_item("flowers:waterlily", {
		groups = {falling_node = 1, float = 1, bouncy = 1, waving = 3, snappy = 3, flower = 1, flammable = 1},
		floodable = false,
	})
	minetest.override_item("flowers:waterlily_waving", {
		groups = {falling_node = 1, float = 1, bouncy = 1, waving = 3, snappy = 3, flower = 1, flammable = 1},
		floodable = false,
	})
end
