-- visuals.lua
-- Phase 4: Visuals and Audio (SWE)

local settings = realistic_fluids.settings
local BLOCK_SIZE = 16

-- Register 8 animated flowing nodes (param2 0-7)
for i = 0, 7 do
	minetest.register_node("realistic_fluids:water_flowing_" .. i, {
		description = "Flowing Water (SWE Level " .. i .. ")",
		drawtype = "flowingliquid",
		tiles = {
			{
				name = "default_water_source_animated.png",
				animation = {
					type = "vertical_frames",
					aspect_w = 16,
					aspect_h = 16,
					length = 2.0,
				},
			},
		},
		special_tiles = {
			{
				name = "default_water_flowing_animated.png",
				backface_culling = false,
				animation = {
					type = "vertical_frames",
					aspect_w = 16,
					aspect_h = 16,
					length = 0.8,
				},
			},
			{
				name = "default_water_flowing_animated.png",
				backface_culling = true,
				animation = {
					type = "vertical_frames",
					aspect_w = 16,
					aspect_h = 16,
					length = 0.8,
				},
			},
		},
		paramtype = "light",
		paramtype2 = "flowingliquid",
		light_source = math.max(0, default.LIGHT_MAX - 1 - (7 - i)),
		walkable = false,
		pointable = false,
		diggable = false,
		buildable_to = true,
		is_ground_content = false,
		drop = "",
		drowning = 1,
		liquidtype = "flowing",
		liquid_alternative_flowing = "realistic_fluids:water_flowing_" .. i,
		liquid_alternative_source = "default:water_source",
		liquid_viscosity = 1,
		post_effect_color = {a = 103, r = 30, g = 60, b = 90},
		groups = {water = 3, liquid = 3, not_in_creative_inventory = 1},
		sounds = default.node_sound_water_defaults(),
	})
end

-- Foam Particles at high velocity
minetest.register_globalstep(function(dtime)
	if settings.disable_lbm or math.random() > 0.2 then return end
	
	for _, grid in pairs(realistic_fluids.grids) do
		if grid.active then
			local sim = grid.sim
			for z = 0, BLOCK_SIZE - 1 do
				for x = 0, BLOCK_SIZE - 1 do
					local h = sim:get_water_height(x, z)
					if h > 0.1 then
						local ux, uz = sim:get_velocity(x, z)
						local speed = math.sqrt(ux*ux + uz*uz)
						
						if speed > 2.0 then
							-- Spawn foam on surface
							local idx = sim:get_index(x, z)
							local b = grid.base_y[idx]
							
							local pos = {
								x = grid.block_pos.x + x,
								y = b + h + 0.1,
								z = grid.block_pos.z + z
							}
							
							minetest.add_particle({
								pos = pos,
								velocity = {x = ux, y = 0.1, z = uz},
								acceleration = {x = 0, y = -1, z = 0},
								expirationtime = 0.5 + math.random() * 0.5,
								size = 1 + math.random() * 2,
								collisiondetection = true,
								collision_removal = true,
								texture = "bubble.png",
								glow = 1
							})
						end
					end
				end
			end
		end
	end
end)

-- Ambient sound near fast water
local sound_timer = 0
minetest.register_globalstep(function(dtime)
	if settings.disable_lbm then return end
	
	sound_timer = sound_timer + dtime
	if sound_timer < 2.0 then return end
	sound_timer = 0
	
	for _, player in ipairs(minetest.get_connected_players()) do
		local ppos = player:get_pos()
		local bpos = {
			x = math.floor(ppos.x / BLOCK_SIZE) * BLOCK_SIZE,
			y = 0,
			z = math.floor(ppos.z / BLOCK_SIZE) * BLOCK_SIZE
		}
		
		local hash = bpos.x .. "," .. bpos.z
		local grid = realistic_fluids.grids[hash]
		
		if grid and grid.active then
			local sim = grid.sim
			local max_speed = 0
			local sx, sz = 0, 0
			
			for z = 0, BLOCK_SIZE - 1 do
				for x = 0, BLOCK_SIZE - 1 do
					local h = sim:get_water_height(x, z)
					if h > 0.1 then
						local ux, uz = sim:get_velocity(x, z)
						local spd = ux*ux + uz*uz
						if spd > max_speed then
							max_speed = spd
							sx, sz = x, z
						end
					end
				end
			end
			
			if max_speed > 2.0 then
				minetest.sound_play("default_water_flowing", {
					pos = {x = bpos.x + sx, y = ppos.y, z = bpos.z + sz},
					max_hear_distance = 16,
					gain = math.min(1.0, max_speed * 0.1),
				}, true)
			end
		end
	end
end)
