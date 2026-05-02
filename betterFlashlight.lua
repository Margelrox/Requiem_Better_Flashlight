-- ver 1.1.0 - added state machine to detect lighter vs flashlight based on native intensity values, with option to unlock lighter override for testing, and a reset to defaults button

local is_hooked = false

-- default constants
local DEFAULT_SCATTERING = 50
local DEFAULT_INTENSITY = 10000
local DEFAULT_RANGE = 30

-- global configs
local config_scattering = DEFAULT_SCATTERING
local config_intensity = DEFAULT_INTENSITY
local config_range = DEFAULT_RANGE

-- state machine vars
local last_stage_prefix = ""
local light_mode = "Scanning..."
local unlock_lighter = false
local detected_base_intensity = 0.0

re.on_draw_ui(function()
    imgui.text("Better Flashlight:")
    
    local changed_scat, new_scat = imgui.slider_int("Volumetric Scattering", config_scattering, 0, 150)
    if changed_scat then config_scattering = new_scat end

    local changed_int, new_int = imgui.slider_int("Intensity", config_intensity, 0, 100000)
    if changed_int then config_intensity = new_int end

    local changed_range, new_range = imgui.slider_int("Distance", config_range, 10, 200)
    if changed_range then config_range = new_range end

    -- reset button logic
    if imgui.button("Reset to Default Values") then
        config_scattering = DEFAULT_SCATTERING
        config_intensity = DEFAULT_INTENSITY
        config_range = DEFAULT_RANGE
    end

    imgui.spacing()

    -- read stage to update state machine
    local stage_manager = sdk.get_managed_singleton("app.EnvStageManager")
    if stage_manager then
        local current_stage = stage_manager:get_field("_CurrentStageName")
        if current_stage ~= nil then
            local stage_str = tostring(current_stage)
            -- extract first 4 chars (e.g., "st30", "st40")
            local current_prefix = string.sub(stage_str, 1, 4)
            
            -- reset scanner if map prefix changes
            if current_prefix ~= last_stage_prefix then
                light_mode = "Scanning..."
                last_stage_prefix = current_prefix
                detected_base_intensity = 0.0
            end
        end
    end

    -- ui status
    imgui.text_colored("Current Zone Prefix: " .. last_stage_prefix, 0xFF00FFFF)
    
    if light_mode == "Scanning..." then
        imgui.text_colored("Mode: Scanning base values...", 0xFF888888)
    elseif light_mode == "Flashlight" then
        imgui.text_colored("Mode: Tactical Flashlight (Active)", 0xFF00FF00)
    elseif light_mode == "Lighter" then
        imgui.text_colored("Mode: Lighter (Detected: " .. tostring(detected_base_intensity) .. ")", 0xFF00A5FF)
    end

    imgui.spacing()

    -- lighter override lock
    local changed_lock, new_lock = imgui.checkbox("Unlock Lighter Override", unlock_lighter)
    if changed_lock then unlock_lighter = new_lock end

    imgui.spacing()

    if not is_hooked then
        if imgui.button("Initialize Flashlight Hooking") then
            local t_flash = sdk.find_type_definition("app.FlashLightParam")
            if not t_flash then return end

            local method = t_flash:get_method("copyTo") 
            if method then
                sdk.hook(
                    method,
                    function(args)
                        local instance = sdk.to_managed_object(args[2])
                        if instance then
                            local spot = instance:get_field("_SpotLightParam")
                            
                            if spot then
                                -- state 1: scanning native value
                                if light_mode == "Scanning..." then
                                    local current_val = spot:get_field("_Intensity")
                                    
                                    -- ignore 0.0 to avoid false triggers on loading screens
                                    if current_val and current_val > 0.0 then
                                        detected_base_intensity = current_val
                                        
                                        if current_val >= 10000.0 then
                                            light_mode = "Flashlight"
                                        else
                                            light_mode = "Lighter"
                                        end
                                    end
                                end
                                
                                -- state 2: applying logic based on mode and lock
                                local should_apply = false
                                
                                if light_mode == "Flashlight" then
                                    should_apply = true
                                elseif light_mode == "Lighter" and unlock_lighter == true then
                                    should_apply = true
                                end
                                
                                if should_apply then
                                    instance:call("set_VolumetricScatteringIntensity", config_scattering)
                                    spot:set_field("_Intensity", config_intensity)
                                    
                                    local success = pcall(function() spot:set_field("_ReferenceEffectiveRange", config_range) end)
                                    if not success then
                                        spot:write_float(0xA8, config_range)
                                    end
                                end
                            end
                        end
                    end,
                    function(retval) return retval end
                )
                is_hooked = true
            end
        end
    else
        imgui.text_colored("Status: Hooked", 0xFF00FF00)
    end
end)