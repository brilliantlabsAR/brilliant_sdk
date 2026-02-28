local data = require('data.min')
local code = require('code.min')
local battery = require('battery.min')
local text_sprite_block = require('text_sprite_block.min')
local image_sprite_block = require('image_sprite_block.min')
local TextLayout = require("text_layout")
local SpeechLayout = require("speech_layout")
local EncounterLayout = require("encounter_layout")

-- Phone to Frame flags
REC_MSG = 0x40
SPEECH_MSG = 0x41
TSB_MSG = 0x50
CLEAR_TSB_MSG = 0x51
ISB_MSG = 0x52
CLEAR_ISB_MSG = 0x53
SET_LAYOUT_MSG = 0x60

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[REC_MSG] = code.parse_code
data.parsers[SPEECH_MSG] = code.parse_code
data.parsers[TSB_MSG] = text_sprite_block.parse_text_sprite_block
data.parsers[CLEAR_TSB_MSG] = code.parse_code
data.parsers[ISB_MSG] = image_sprite_block.parse_image_sprite_block
data.parsers[CLEAR_ISB_MSG] = code.parse_code
data.parsers[SET_LAYOUT_MSG] = code.parse_code

-- Main app loop
function app_loop()
    local ui = TextLayout:new()
    local last_time = frame.time.utc() - 0.05 -- Initialize to one frame ago
    print("Layout app started")

    local last_batt_update = 0

    while true do
        local current_time = frame.time.utc()
        local dt = current_time - last_time

        -- process any raw data items, if ready
        local items_ready = data.process_raw_items()

        -- one or more full messages received
        if items_ready > 0 then

            if (data.app_data[SET_LAYOUT_MSG] ~= nil) then
                local layout_code = data.app_data[SET_LAYOUT_MSG].value

                if layout_code == 1 then
                    ui = TextLayout:new()
                elseif layout_code == 2 then
                    ui = SpeechLayout:new()
                elseif layout_code == 3 then
                    ui = EncounterLayout:new()
                else
                    print("Warning: Received unknown layout code: " .. tostring(layout_code) .. ". Ignoring.")
                end

                data.app_data[SET_LAYOUT_MSG] = nil
                collectgarbage()
            end

            if (data.app_data[REC_MSG] ~= nil) then
                if data.app_data[REC_MSG].value == 1 then
                    ui.header:set_recording(true)
                else
                    ui.header:set_recording(false)
                end
                data.app_data[REC_MSG] = nil
            end

            if (data.app_data[SPEECH_MSG] ~= nil) then
                if getmetatable(ui) == SpeechLayout then
                    if data.app_data[SPEECH_MSG].value == 1 then
                        ui.body.speech_wave:start() -- Start speech wave animation
                    else
                        ui.body.speech_wave:stop() -- Stop speech wave animation
                    end
                else
                    print("Warning: Received SPEECH_MSG but current layout is not SpeechLayout. Ignoring.")
                end
                data.app_data[SPEECH_MSG] = nil
            end

            if (data.app_data[CLEAR_TSB_MSG] ~= nil) then
                if getmetatable(ui) == TextLayout or getmetatable(ui) == EncounterLayout then
                    ui.body:clear_lines()

                    if (data.app_data[TSB_MSG] ~= nil) then
                        data.app_data[TSB_MSG] = nil
                        collectgarbage()
                    end
                else
                    print("Warning: Received CLEAR_TSB_MSG but current layout is not TextLayout or EncounterLayout. Ignoring.")
                end
                data.app_data[CLEAR_TSB_MSG] = nil
            end

            if (data.app_data[TSB_MSG] ~= nil) then
                if getmetatable(ui) == TextLayout or getmetatable(ui) == EncounterLayout then
                    local tsb = data.app_data[TSB_MSG]
                    -- clear the text area before drawing new text sprites
                    frame.display.rect(ui.body.x, ui.body.y, tsb.width, tsb.max_display_lines * tsb.line_height, 0x000000, true)

                    if #tsb.sprites > 0 then
                        ui.body:set_lines(tsb.sprites, tsb.line_height)
                    end
                else
                    print("Warning: Received TSB_MSG but current layout is not TextLayout or EncounterLayout. Ignoring.")
                end
            end

            if (data.app_data[CLEAR_ISB_MSG] ~= nil) then
                if getmetatable(ui) == EncounterLayout then
                    ui.image:clear_lines()
                    ui.bg:invalidate() -- force a full redraw (including bg_view) to clear the image area because the rectangle intersects with the circular boundary and we don't want to draw over it

                    if (data.app_data[ISB_MSG] ~= nil) then
                        data.app_data[ISB_MSG] = nil
                        collectgarbage()
                    end
                else
                    print("Warning: Received CLEAR_ISB_MSG but current layout is not EncounterLayout. Ignoring.")
                end
                data.app_data[CLEAR_ISB_MSG] = nil
            end

            if (data.app_data[ISB_MSG] ~= nil) then
                if getmetatable(ui) == EncounterLayout then
                    local isb = data.app_data[ISB_MSG]

                    -- for progressive drawing, use "#isb.sprites > 0" but I'll wait for all of them
                    -- 128px with 16px strips so 8 strips total
                    if #isb.sprites == 8 then
                        ui.image:set_lines(isb.sprites, isb.sprite_line_height)
                    end
                else
                    print("Warning: Received ISB_MSG but current layout is not EncounterLayout. Ignoring.")
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