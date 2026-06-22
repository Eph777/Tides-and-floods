-- climate_integration.lua
-- Triggers Climate API / Regional Weather effects when a flood is active
-- in the realistic_rising_floods mod, creating an immersive storm atmosphere.
--
-- Requires: climate_api and regional_weather mods installed and enabled.
--
-- Flood-relevant weather presets forced ON during rising/periodic floods:
--   • regional_weather:rain_heavy  — torrential downpour
--   • regional_weather:storm       — howling wind
--   • regional_weather:fog         — low-visibility mist
--
-- Environment overrides applied:
--   • Humidity cranked up to 90+ (ensures rain activation)
--   • Wind set to strong gusts (supports storm preset)
--   • Base heat set warm enough to keep precipitation as rain, not snow
--
-- All presets/overrides are restored to "auto" when flood stops.

local FLOOD_PRESETS = {
	"regional_weather:rain_heavy",
	"regional_weather:storm",
	"regional_weather:fog",
}

-- Non-flood presets we explicitly turn OFF so they don't fight the storm
local SUPPRESSED_PRESETS = {
	"regional_weather:snow",
	"regional_weather:snow_heavy",
	"regional_weather:sandstorm",
	"regional_weather:pollen",
}

-- State tracking
local climate_active = false  -- are we currently forcing climate?
local check_interval = 2.0    -- seconds between checks
local check_timer = 0

-- Detect whether climate_api is actually loaded
local function climate_available()
	return minetest.global_exists("climate_api") and
	       minetest.global_exists("climate_mod")
end

-- Determine if we are in a flood state.
-- A "flood" is defined as:
--   - Tide mode is "rising" and sea level is above the base level, OR
--   - Tide mode is "periodic" and current sea level > the periodic low mark + 1
local function is_flood_active()
	if not realistic_rising_floods or not realistic_rising_floods.tide_settings then
		return false
	end
	local mode = realistic_rising_floods.tide_settings.mode
	local sl   = realistic_rising_floods.sealevel or 1
	local base = realistic_rising_floods.settings.ocean.sea_level or 1

	if mode == "rising" then
		-- Flood once sea has risen at least 1 block above base
		return sl > base
	elseif mode == "periodic" then
		local low  = realistic_rising_floods.tide_settings.tide_low or 1
		-- Flood during the upper half of the tidal cycle
		return sl > low + 1
	end
	return false
end

-- Force a weather preset ON via the climate_mod internal API
local function force_weather_on(preset_name)
	if climate_mod.forced_weather then
		climate_mod.forced_weather[preset_name] = true
	end
end

-- Force a weather preset OFF
local function force_weather_off(preset_name)
	if climate_mod.forced_weather then
		climate_mod.forced_weather[preset_name] = false
	end
end

-- Reset a weather preset back to automatic
local function force_weather_auto(preset_name)
	if climate_mod.forced_weather then
		climate_mod.forced_weather[preset_name] = nil
	end
end

-- Apply flood environment overrides
local function apply_flood_environment()
	if not climate_mod.forced_enviroment then return end  -- note: typo is in original climate_api code

	-- Crank humidity way up to trigger heavy rain conditions
	climate_mod.forced_enviroment.humidity = 95

	-- Set temperature warm enough for rain (not snow). 
	-- Regional weather uses Fahrenheit internally; 70°F = pleasant warm rain
	climate_mod.forced_enviroment.heat = 70

	-- Strong wind for storm effects
	-- Wind is a {x, z} vector; set strong gusts
	climate_mod.forced_enviroment.wind = {x = 4, y = 0, z = 3}
end

-- Clear all environment overrides
local function clear_flood_environment()
	if not climate_mod.forced_enviroment then return end

	climate_mod.forced_enviroment.humidity = nil
	climate_mod.forced_enviroment.heat = nil
	climate_mod.forced_enviroment.wind = nil
end

-- Activate flood climate
local function activate_flood_climate()
	if climate_active then return end
	climate_active = true

	minetest.log("action", "[realistic_rising_floods] Flood detected — activating storm climate")

	-- Force flood-appropriate weather presets ON
	for _, preset in ipairs(FLOOD_PRESETS) do
		force_weather_on(preset)
	end

	-- Suppress conflicting weather
	for _, preset in ipairs(SUPPRESSED_PRESETS) do
		force_weather_off(preset)
	end

	-- Override environment values
	apply_flood_environment()

	-- Notify all players
	for _, player in ipairs(minetest.get_connected_players()) do
		minetest.chat_send_player(player:get_player_name(),
			"*** Storm surge! Heavy rain and strong winds as the sea rises...")
	end
end

-- Deactivate flood climate — restore everything to auto
local function deactivate_flood_climate()
	if not climate_active then return end
	climate_active = false

	minetest.log("action", "[realistic_rising_floods] Flood subsiding — restoring normal climate")

	-- Reset all presets to auto
	for _, preset in ipairs(FLOOD_PRESETS) do
		force_weather_auto(preset)
	end
	for _, preset in ipairs(SUPPRESSED_PRESETS) do
		force_weather_auto(preset)
	end

	-- Clear environment overrides
	clear_flood_environment()

	-- Notify all players
	for _, player in ipairs(minetest.get_connected_players()) do
		minetest.chat_send_player(player:get_player_name(),
			"*** The storm passes... skies clearing.")
	end
end

-- ============================================================
-- Globalstep: periodically check flood state and toggle climate
-- ============================================================
minetest.register_globalstep(function(dtime)
	check_timer = check_timer + dtime
	if check_timer < check_interval then return end
	check_timer = 0

	if not climate_available() then return end

	local flooding = is_flood_active()

	if flooding and not climate_active then
		activate_flood_climate()
	elseif not flooding and climate_active then
		deactivate_flood_climate()
	end
end)

-- ============================================================
-- Chat command to manually trigger/stop flood climate
-- ============================================================
minetest.register_chatcommand("floodclimate", {
	params = "<on|off|auto>",
	description = "Manually control flood climate effects (on = force storm, off = force clear, auto = tie to sea level)",
	privs = {sealevel = true},
	func = function(name, param)
		if not climate_available() then
			return false, "Climate API is not installed or not loaded."
		end

		param = param:trim():lower()

		if param == "on" then
			activate_flood_climate()
			return true, "Flood climate forced ON."
		elseif param == "off" then
			deactivate_flood_climate()
			return true, "Flood climate forced OFF."
		elseif param == "auto" then
			-- Reset to automatic flood-tracking behavior
			if climate_active and not is_flood_active() then
				deactivate_flood_climate()
			elseif not climate_active and is_flood_active() then
				activate_flood_climate()
			end
			return true, "Flood climate set to AUTO (tracks sea level)."
		else
			return false, "Usage: /floodclimate <on|off|auto>"
		end
	end
})

minetest.log("action", "[realistic_rising_floods] Climate integration loaded (climate_api detected: "
	.. tostring(climate_available()) .. ")")
