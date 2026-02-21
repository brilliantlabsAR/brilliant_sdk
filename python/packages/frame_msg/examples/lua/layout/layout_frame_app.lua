local data = require('data.min')
local code = require('code.min')
local NoaLayout = require("noa_layout")

-- Phone to Frame flags
REC_MSG = 0x40
SPEECH_MSG = 0x41

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[REC_MSG] = code.parse_code
data.parsers[SPEECH_MSG] = code.parse_code

local ui = NoaLayout:new()
local last_time = frame.time.utc() - 0.05 -- Initialize to one frame ago
local start_time = last_time
print("Layout app started. Running main loop...")

local step_one_done = false
local step_two_done = false

while true do
    local current_time = frame.time.utc()
    local dt = current_time - last_time

    -- process any raw data items, if ready
    local items_ready = data.process_raw_items()

    -- one or more full messages received
    if items_ready > 0 then

        if (data.app_data[REC_MSG] ~= nil) then
            if data.app_data[REC_MSG].value == 1 then
                ui.header:set_recording(true)
            else
                ui.header:set_recording(false)
            end
        end

        if (data.app_data[SPEECH_MSG] ~= nil) then
            if data.app_data[SPEECH_MSG].value == 1 then
                ui.footer.speech_wave:start() -- Start speech wave animation
            else
                ui.footer.speech_wave:stop() -- Stop speech wave animation
            end
        end

        --     ui.body:push_line("Message number " .. tostring(1))
        --     ui.body:push_line("Message number " .. tostring(2))
        --     ui.body:push_line("Message number " .. tostring(3))
        --     ui.body:push_line("Message number " .. tostring(4))
    end

    ui:update(dt)
    ui:render()

    if current_time - start_time > 30.0 then
        print("Exiting main loop after 30 seconds")
        break
    end

    frame.sleep(0.05) -- Sleep to limit frame rate
    last_time = current_time
end