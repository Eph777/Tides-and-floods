-- ocean_manager.lua
-- Tide and flood controller for realistic_fluids: manages periodic tides, rising sea levels,
-- and registers chat commands to control the ocean state.

local storage = minetest.get_mod_storage()

-- Load a setting from mod storage with a fallback default value
local function load_setting(key, default)
	local val = storage:get_string(key)
	if val ~= "" then
		if type(default) == "number" then
			return tonumber(val) or default
		elseif type(default) == "boolean" then
			return val == "true"
		else
			return val
		end
	end
	return default
end

-- Tide and flood settings
realistic_fluids.tide_settings = {
	mode = load_setting("mode", "manual"), -- manual, periodic, rising
	rising_speed = load_setting("rising_speed", 2.0), -- nodes per minute
	rising_max = load_setting("rising_max", 15),
	rising_min = load_setting("rising_min", 1),
	tide_low = load_setting("tide_low", 1),
	tide_high = load_setting("tide_high", 5),
	tide_period = load_setting("tide_period", 10.0), -- minutes
}

-- Current active sea level (integer)
local base_sealevel = tonumber(storage:get_int("sealevel"))
if not base_sealevel or base_sealevel == 0 then
	base_sealevel = realistic_fluids.settings.ocean.sea_level or 1
	storage:set_int("sealevel", base_sealevel)
end
realistic_fluids.sealevel = base_sealevel

-- Fractional target level for smooth progression (rising mode)
local fractional_sealevel = tonumber(storage:get("fractional_sealevel")) or base_sealevel

-- Set the sea level and broadcast changes
function realistic_fluids.set_sealevel(height)
	height = math.floor(tonumber(height))
	if height == realistic_fluids.sealevel then return end
	realistic_fluids.sealevel = height
	storage:set_int("sealevel", height)
	minetest.chat_send_all("[realistic_fluids] Sea level set to: " .. height)
end

-- Global time tracker
local global_time = 0

minetest.register_globalstep(function(dtime)
	if not realistic_fluids.settings.ocean.enabled then return end

	global_time = global_time + dtime
	-- Export global time for buoyancy
	realistic_fluids.ocean_time = global_time * (realistic_fluids.settings.ocean.wave_speed or 1.0)

	local mode = realistic_fluids.tide_settings.mode

	if mode == "rising" then
		-- Rise speed in nodes per second
		local speed_sec = (realistic_fluids.tide_settings.rising_speed or 2.0) / 60.0
		local max_h = realistic_fluids.tide_settings.rising_max or 15
		local min_h = realistic_fluids.tide_settings.rising_min or 1

		fractional_sealevel = fractional_sealevel + speed_sec * dtime
		if fractional_sealevel > max_h then
			fractional_sealevel = max_h
		elseif fractional_sealevel < min_h then
			fractional_sealevel = min_h
		end

		storage:set_string("fractional_sealevel", tostring(fractional_sealevel))

		local next_y = math.floor(fractional_sealevel)
		if next_y ~= realistic_fluids.sealevel then
			realistic_fluids.set_sealevel(next_y)
		end

	elseif mode == "periodic" then
		local low = realistic_fluids.tide_settings.tide_low or 1
		local high = realistic_fluids.tide_settings.tide_high or 5
		local period_sec = (realistic_fluids.tide_settings.tide_period or 10.0) * 60.0

		if period_sec > 0 then
			local amplitude = (high - low) / 2
			local mid = (high + low) / 2
			-- Sine wave oscillation
			local angle = (2 * math.pi * global_time) / period_sec
			local next_y = math.floor(mid + amplitude * math.sin(angle) + 0.5)

			if next_y ~= realistic_fluids.sealevel then
				realistic_fluids.set_sealevel(next_y)
			end
		end
	end
end)

-- ============================================================
-- Chat Commands
-- ============================================================

minetest.register_privilege("sealevel", "player can use /sealevel and /tides commands")

-- /tides command: configure modes and settings
minetest.register_chatcommand("tides", {
	params = "status | mode <manual|periodic|rising> | speed <nodes_per_min> | range <low> <high> | period <minutes> | max <height> | min <height>",
	description = "Configure realistic_fluids ocean tides and flooding",
	privs = {sealevel = true},
	func = function(name, param)
		local args = {}
		for word in param:gmatch("%S+") do
			table.insert(args, word)
		end

		local sub = args[1]
		if not sub or sub == "status" then
			local s = realistic_fluids.tide_settings
			local status_str = "\n[realistic_fluids Tides Status]:"
				.. "\n- Mode: " .. tostring(s.mode)
				.. "\n- Current sea level: " .. tostring(realistic_fluids.sealevel)
				.. "\n- Rising Speed: " .. tostring(s.rising_speed) .. " nodes/min"
				.. "\n- Rising Range: min=" .. tostring(s.rising_min) .. ", max=" .. tostring(s.rising_max)
				.. "\n- Periodic Range: low=" .. tostring(s.tide_low) .. ", high=" .. tostring(s.tide_high)
				.. "\n- Periodic Period: " .. tostring(s.tide_period) .. " min"
			return true, status_str
		end

		if sub == "mode" then
			local m = args[2]
			if m == "manual" or m == "periodic" or m == "rising" then
				realistic_fluids.tide_settings.mode = m
				storage:set_string("mode", m)
				if m == "rising" then
					fractional_sealevel = realistic_fluids.sealevel
					storage:set_string("fractional_sealevel", tostring(fractional_sealevel))
				end
				return true, "Tide mode set to: " .. m
			else
				return false, "Invalid mode: choose manual, periodic, or rising"
			end
		elseif sub == "speed" then
			local val = tonumber(args[2])
			if val then
				realistic_fluids.tide_settings.rising_speed = val
				storage:set_string("rising_speed", tostring(val))
				return true, "Tide rising speed set to: " .. val .. " nodes per minute"
			else
				return false, "Invalid speed value"
			end
		elseif sub == "range" then
			local low = tonumber(args[2])
			local high = tonumber(args[3])
			if low and high then
				if low > high then low, high = high, low end
				realistic_fluids.tide_settings.tide_low = low
				realistic_fluids.tide_settings.tide_high = high
				storage:set_string("tide_low", tostring(low))
				storage:set_string("tide_high", tostring(high))
				return true, "Periodic tide range set to low=" .. low .. ", high=" .. high
			else
				return false, "Invalid range values: usage `/tides range <low> <high>`"
			end
		elseif sub == "period" then
			local val = tonumber(args[2])
			if val and val > 0 then
				realistic_fluids.tide_settings.tide_period = val
				storage:set_string("tide_period", tostring(val))
				return true, "Periodic tide period set to: " .. val .. " minutes"
			else
				return false, "Invalid period value (must be > 0)"
			end
		elseif sub == "max" then
			local val = tonumber(args[2])
			if val then
				realistic_fluids.tide_settings.rising_max = val
				storage:set_string("rising_max", tostring(val))
				return true, "Rising tide max height set to: " .. val
			else
				return false, "Invalid max height value"
			end
		elseif sub == "min" then
			local val = tonumber(args[2])
			if val then
				realistic_fluids.tide_settings.rising_min = val
				storage:set_string("rising_min", tostring(val))
				return true, "Rising tide min height set to: " .. val
			else
				return false, "Invalid min height value"
			end
		else
			return false, "Unknown subcommand: choose status, mode, speed, range, period, min, max"
		end
	end
})

-- /sealevel command: set base sea level manually
minetest.register_chatcommand("sealevel", {
	params = "<height>",
	description = "Set base sea level manually",
	privs = {sealevel = true},
	func = function(name, param)
		local val = tonumber(param)
		if not val then
			return false, "Current sea level is: " .. tostring(realistic_fluids.sealevel)
		else
			realistic_fluids.set_sealevel(val)
			fractional_sealevel = val
			storage:set_string("fractional_sealevel", tostring(val))
			return true, "Sea level set to: " .. val
		end
	end
})

-- ============================================================
-- Backward compatibility metatable for tidesandfloods
-- ============================================================
tidesandfloods = {}
setmetatable(tidesandfloods, {
	__index = function(t, k)
		if k == "sealevel" then
			return realistic_fluids.sealevel
		elseif k == "water_level" then
			return realistic_fluids.settings.ocean.sea_level
		end
	end,
	__newindex = function(t, k, v)
		if k == "sealevel" then
			realistic_fluids.set_sealevel(v)
		end
	end
})
