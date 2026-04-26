local is_hooked = false

-- global vars
local config_scattering = 50.0
local config_intensity = 8000.0
local config_range = 30.0

re.on_draw_ui(function()
    imgui.text("Better Flashlight:")
    
    local changed_scat, new_scat = imgui.slider_float("Volumetric Scattering", config_scattering, 0.0, 150.0)
    if changed_scat then config_scattering = new_scat end

    local changed_int, new_int = imgui.slider_float("Intensity", config_intensity, 0.0, 100000.0)
    if changed_int then config_intensity = new_int end

    local changed_range, new_range = imgui.slider_float("Distance", config_range, 10.0, 200.0)
    if changed_range then config_range = new_range end

    imgui.spacing()

    if not is_hooked then
        if imgui.button("Initialize Flashlight Hooking") then
            local t_flash = sdk.find_type_definition("app.FlashLightParam")
            if not t_flash then return end

            local method = t_flash:get_method("copyTo") 
            if method then
                print("Searching flashlight")
                sdk.hook(
                    method,
                    function(args)
                        local instance = sdk.to_managed_object(args[2])
                        if instance then
                            instance:call("set_VolumetricScatteringIntensity", config_scattering)
                            
                            local spot = instance:get_field("_SpotLightParam")
                            if spot then
                                spot:set_field("_Intensity", config_intensity)
                                
                                -- Search for the field, if it doesn't exist, write to memory directly
                                local success = pcall(function() spot:set_field("_ReferenceEffectiveRange", config_range) end)
                                
                                -- Memory inyection
                                if not success then
                                    spot:write_float(0xA8, config_range)
                                end
                            end
                        end
                    end,
                    function(retval) return retval end
                )
                is_hooked = true
            else
                print("Error: Method not found.")
            end
        end
    else
        imgui.text_colored("Status: Active", 0xFF00FF00)
    end
end)