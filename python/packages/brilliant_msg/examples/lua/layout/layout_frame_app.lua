local data = require('data.min')
local code = require('code.min')
local text_sprite_block = require('text_sprite_block.min')
local NoaLayout = require("noa_layout")

-- Phone to Frame flags
REC_MSG = 0x40
SPEECH_MSG = 0x41
TSB_MSG = 0x50
CLEAR_TXT_MSG = 0x51

local ui = NoaLayout:new()
local last_time = frame.time.utc() - 0.05 -- Initialize to one frame ago
local start_time = last_time
print("Layout app started. Running main loop...")

-- accumulator for text sprite block (persists across loop iterations)
local current_tsb = nil

local step_one_done = false
local step_two_done = false

while true do
    local current_time = frame.time.utc()
    local dt = current_time - last_time

    -- process any raw data items, if ready
    local items = data.process_raw_items()

    for i = 1, #items do
        local flag = items[i][1]
        local raw = items[i][2]

        if flag == REC_MSG then
            local msg = code.parse_code(raw)
            if msg.value == 1 then
                ui.header:set_recording(true)
            else
                ui.header:set_recording(false)
            end

        elseif flag == SPEECH_MSG then
            local msg = code.parse_code(raw)
            if msg.value == 1 then
                ui.footer.speech_wave:start() -- Start speech wave animation
            else
                ui.footer.speech_wave:stop() -- Stop speech wave animation
            end

        elseif flag == CLEAR_TXT_MSG then
            ui.body:clear_lines()
            if current_tsb ~= nil then
                current_tsb = nil
                collectgarbage()
            end

        elseif flag == TSB_MSG then
            current_tsb = text_sprite_block.parse_text_sprite_block(raw, current_tsb)
            if current_tsb ~= nil then
                print('Received text sprite block with line_height=' .. tostring(current_tsb.line_height) .. ' and width=' .. tostring(current_tsb.width))
                -- clear the text area before drawing new text sprites
                frame.display.rect(ui.body.x, ui.body.y, current_tsb.width, current_tsb.max_display_lines * current_tsb.line_height, 0x000000, true)

                if #current_tsb.sprites > 0 then
                    print('Setting ' .. tostring(#current_tsb.sprites) .. ' text sprites in body view')
                    ui.body:set_lines(current_tsb.sprites, current_tsb.line_height)
                end
            end
        end
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