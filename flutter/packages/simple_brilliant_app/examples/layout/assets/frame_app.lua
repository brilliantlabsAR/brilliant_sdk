local data = require('data.min')
local code = require('code.min')
local battery = require('battery.min')
local text_sprite_block = require('text_sprite_block.min')
local image_sprite_block = require('image_sprite_block.min')
local TextLayout = require("text_layout.min")
local SpeechLayout = require("speech_layout.min")
local EncounterLayout = require("encounter_layout.min")

-- Phone to Frame flags
local REC_MSG = 0x40
local SPEECH_WAVE_MSG = 0x70
local TSB_MSG = 0x50
local CLEAR_TSB_MSG = 0x51
local ISB_MSG = 0x52
local CLEAR_ISB_MSG = 0x53
local SET_LAYOUT_MSG = 0x60

-- message parsers, keyed by message flag
local parsers = {}
parsers[REC_MSG] = code.parse_code
parsers[SPEECH_WAVE_MSG] = code.parse_code
parsers[TSB_MSG] = text_sprite_block.parse_text_sprite_block
parsers[CLEAR_TSB_MSG] = code.parse_code
parsers[ISB_MSG] = image_sprite_block.parse_image_sprite_block
parsers[CLEAR_ISB_MSG] = code.parse_code
parsers[SET_LAYOUT_MSG] = code.parse_code

-- Main app loop
function app_loop()
    local ui = TextLayout:new()
    local last_time = frame.time.utc() - 0.05 -- Initialize to one frame ago
    print("Layout app started")

    local last_batt_update = 0

    -- app-owned state for accumulating message types (TSB, ISB)
    local state = {}

    -- message handlers, dispatched in arrival order by the main loop
    local handlers = {}

    handlers[SET_LAYOUT_MSG] = function(item)
        local layout_code = item.value

        if layout_code == 1 then
            ui = TextLayout:new()
        elseif layout_code == 2 then
            ui = SpeechLayout:new()
        elseif layout_code == 3 then
            ui = EncounterLayout:new()
        else
            print("Warning: Received unknown layout code: " .. tostring(layout_code) .. ". Ignoring.")
            return
        end

        -- blank out the whole layout first
        ui:clear()
        ui:invalidate()
        collectgarbage()
    end

    handlers[REC_MSG] = function(item)
        if item.value == 1 then
            ui.header:set_recording(true)
        else
            ui.header:set_recording(false)
        end
    end

    handlers[SPEECH_WAVE_MSG] = function(item)
        if ui:is("SpeechLayout") then
            if item.value == 1 then
                ui.body.speech_wave:start()
            else
                ui.body.speech_wave:stop()
            end
        else
            print("Warning: Received SPEECH_WAVE_MSG but current layout is not SpeechLayout. Ignoring.")
        end
    end

    handlers[CLEAR_TSB_MSG] = function(item)
        if ui:is("EncounterLayout") or ui:is("TextLayout") then
            ui.body:clear_lines()
            state[TSB_MSG] = nil
            collectgarbage()
        else
            print("Warning: Received CLEAR_TSB_MSG but current layout is not TextLayout or EncounterLayout. Ignoring.")
        end
    end

    handlers[TSB_MSG] = function(item)
        if ui:is("EncounterLayout") or ui:is("TextLayout") then
            -- clear the text area before drawing new text sprites
            if frame.HARDWARE_VERSION ~= 'Frame' then
                frame.display.rect(ui.body.x, ui.body.y, item.width, item.max_display_lines * item.line_height, 0x000000, true)
            end

            if #item.sprites > 0 then
                ui.body:set_lines(item.sprites, item.line_height)
            end
        else
            print("Warning: Received TSB_MSG but current layout is not TextLayout or EncounterLayout. Ignoring.")
        end
    end

    handlers[CLEAR_ISB_MSG] = function(item)
        if ui:is("EncounterLayout") then
            ui.image:clear_lines()
            ui.bg:invalidate() -- force a full redraw (including bg_view) to clear the image area because the rectangle intersects with the circular boundary
            state[ISB_MSG] = nil
            collectgarbage()
        else
            print("Warning: Received CLEAR_ISB_MSG but current layout is not EncounterLayout. Ignoring.")
        end
    end

    handlers[ISB_MSG] = function(item)
        if ui:is("EncounterLayout") then
            -- for progressive drawing, use "#item.sprites > 0" but I'll wait for all of them
            -- 128px with 16px strips so 8 strips total
            if #item.sprites == 8 then
                ui.image:set_lines(item.sprites, item.sprite_line_height)
            end
        else
            print("Warning: Received ISB_MSG but current layout is not EncounterLayout. Ignoring.")
        end
    end

    while true do
        local current_time = frame.time.utc()
        local dt = current_time - last_time

        -- drain the message queue, parse and dispatch in arrival order
        local items = data.process_raw_items()
        for i = 1, #items do
            local flag = items[i][1]
            local raw  = items[i][2]

            if parsers[flag] == nil then
                print('Error: No parser for flag: ' .. tostring(flag))
            else
                local parsed

                -- accumulating types: thread app-owned state through the parser
                if flag == TSB_MSG or flag == ISB_MSG then
                    parsed = parsers[flag](raw, state[flag])
                    state[flag] = parsed
                else
                    parsed = parsers[flag](raw)
                end

                if handlers[flag] ~= nil then
                    handlers[flag](parsed)
                else
                    print('Error: No handler for flag: ' .. tostring(flag))
                end
            end
        end

        ui:update(dt)
        if ui.is_dirty then
            ui:render()
            frame.display.show()
        end

        last_batt_update = battery.send_batt_if_elapsed(last_batt_update, 120)

        frame.sleep(0.02)
        last_time = current_time
    end
end

-- run the main app loop
app_loop()
