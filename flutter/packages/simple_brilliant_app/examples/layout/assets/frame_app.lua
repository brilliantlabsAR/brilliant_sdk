local data = require('data.min')
local code = require('code.min')
local battery = require('battery.min')
local text_sprite_block = require('text_sprite_block.min')
local NoaLayout = require("noa_layout")

-- Phone to Frame flags
REC_MSG = 0x40
SPEECH_MSG = 0x41
TSB_MSG = 0x50
CLEAR_TXT_MSG = 0x51

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[REC_MSG] = code.parse_code
data.parsers[SPEECH_MSG] = code.parse_code
data.parsers[TSB_MSG] = text_sprite_block.parse_text_sprite_block
data.parsers[CLEAR_TXT_MSG] = code.parse_code

-- Main app loop
function app_loop()
    local ui = NoaLayout:new()
    local last_time = frame.time.utc() - 0.05 -- Initialize to one frame ago
    local start_time = last_time
    print("Layout app started. Running main loop...")

    local step_one_done = false
    local step_two_done = false
    local last_batt_update = 0

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

            if (data.app_data[CLEAR_TXT_MSG] ~= nil) then
                ui.body:clear_lines()
                data.app_data[CLEAR_TXT_MSG] = nil

                if (data.app_data[TSB_MSG] ~= nil) then
                    data.app_data[TSB_MSG] = nil
                    collectgarbage()
                end
            end

            if (data.app_data[TSB_MSG] ~= nil) then
                local tsb = data.app_data[TSB_MSG]
                -- clear the text area before drawing new text sprites
                frame.display.rect(ui.body.x, ui.body.y, tsb.width, tsb.max_display_lines * tsb.line_height, 0x000000, true)

                if #tsb.sprites > 0 then
                    ui.body:set_lines(tsb.sprites, tsb.line_height)
                end
            end
        end

        ui:update(dt)
        ui:render()

        last_batt_update = battery.send_batt_if_elapsed(last_batt_update, 120)

        frame.sleep(0.02)
        last_time = current_time
    end
end

-- run the main app loop
app_loop()    