local data = require('data.min')
local battery = require('battery.min')
local sprite = require('sprite.min')
local code = require('code.min')
local text_sprite_block = require('text_sprite_block.min')

-- Phone to Frame flags
TEXT_SPRITE_BLOCK = 0x20
CLEAR_MSG = 0x10

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[TEXT_SPRITE_BLOCK] = text_sprite_block.parse_text_sprite_block
data.parsers[CLEAR_MSG] = code.parse_code

-- Main app loop
function app_loop()
	-- clear the display
	frame.display.text(" ", 1, 1)
	frame.display.show()
    local last_batt_update = 0

    while true do
        rc, err = pcall(
            function()
                -- process any raw data items, if ready
                local items_ready = data.process_raw_items()

                -- one or more full messages received
                if items_ready > 0 then

                    if (data.app_data[TEXT_SPRITE_BLOCK] ~= nil) then
                        -- show the text sprite block
                        local tsb = data.app_data[TEXT_SPRITE_BLOCK]

                        -- it can be that we haven't got any sprites yet
                        local shift_y = 0
                        if tsb.first_sprite_index > 0 then
                            shift_y = tsb.offsets[tsb.first_sprite_index].y

                            for index = tsb.first_sprite_index, tsb.last_sprite_index do
                                local spr = tsb.sprites[index]
                                frame.display.bitmap(1, tsb.offsets[index].y + 1 - shift_y, spr.width, 2^spr.bpp, 0, spr.pixel_data)
                            end

                            frame.display.show()
                            last_text_show = frame.time.utc()
                        end
                    end

                    if (data.app_data[CLEAR_MSG] ~= nil) then
                        -- clear the display
                        frame.display.text(" ", 1, 1)
                        frame.display.show()

                        data.app_data[CLEAR_MSG] = nil
                    end
                end

                -- periodic battery level updates, 120s for a camera app
                last_batt_update = battery.send_batt_if_elapsed(last_batt_update, 120)
                frame.sleep(0.1)
            end
        )
        -- Catch the break signal here and clean up the display
        if rc == false then
            -- send the error back on the stdout stream
            print(err)
            frame.display.text(" ", 1, 1)
            frame.display.show()
            frame.sleep(0.04)
            break
        end
    end
end

-- run the main app loop
app_loop()