local NoaLayout = require("noa_layout")

local ui = NoaLayout:new()
local last_time = frame.time.utc() - 0.05 -- Initialize to one frame ago
local start_time = last_time
print("Layout app started. Running main loop...")

local recording = false
while true do
    local current_time = frame.time.utc()
    local dt = current_time - last_time
    
    if not recording and (current_time - start_time > 3.0) then
        print("Setting recording status set to true after 3 seconds")
        ui.header:set_recording(true)
        ui.header:invalidate() -- Mark header as dirty to trigger redraw
        print("Header is dirty: " .. tostring(ui.header.is_dirty)) -- Debug print to verify state
        -- local recording status
        recording = true
    end

    ui:update(dt)
    ui:render() -- Redraws ONLY if ui.is_dirty was set in the update
    
    frame.sleep(0.05) -- Sleep to limit frame rate
    last_time = current_time

    if current_time - start_time > 60.0 then
        print("Exiting main loop after 60 seconds")
        break
    end
end