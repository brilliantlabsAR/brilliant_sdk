local NoaLayout = require("noa_layout")

local ui = NoaLayout:new()
local last_time = frame.time.utc() - 0.05 -- Initialize to one frame ago
local start_time = last_time
print("Layout app started. Running main loop...")

local step_one_done = false
local step_two_done = false
while true do
    local current_time = frame.time.utc()
    local dt = current_time - last_time
    
    if not step_one_done and (current_time - start_time > 3.0) then
        ui.header:set_recording(true)
        ui.footer.speech_wave:start() -- Start speech wave animation
        ui.body:push_line("Message number " .. tostring(1))
        ui.body:push_line("Message number " .. tostring(2))
        step_one_done = true
    end

    if not step_two_done and (current_time - start_time > 6.0) then
        ui.header:set_recording(false)
        ui.footer.speech_wave:stop() -- Stop speech wave animation
        ui.body:push_line("Message number " .. tostring(3))
        ui.body:push_line("Message number " .. tostring(4))
        step_two_done = true
    end

    ui:update(dt)
    ui:render()
    
    frame.sleep(0.05) -- Sleep to limit frame rate
    last_time = current_time

    if current_time - start_time > 60.0 then
        print("Exiting main loop after 60 seconds")
        break
    end
end