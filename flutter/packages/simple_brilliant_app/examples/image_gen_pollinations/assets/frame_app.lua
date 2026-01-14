local data = require('data.min')
local battery = require('battery.min')
local image_sprite_block = require('image_sprite_block.min')
local plain_text = require('plain_text.min')

-- Phone to Frame flags
TEXT_FLAG = 0x0a
IMAGE_SPRITE_BLOCK = 0x0d

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[TEXT_FLAG] = plain_text.parse_plain_text
data.parsers[IMAGE_SPRITE_BLOCK] = image_sprite_block.parse_image_sprite_block

-- draw the current text on the display
function print_text(text_string)
    local i = 0
    for line in text_string:gmatch("([^\n]*)\n?") do
        if line ~= "" then
			if frame.HARDWARE_VERSION == "Frame" then
                if i * 60 + 1 > 400 then
                    break
                end
				frame.display.text(line, 1, i * 60 + 1)
			else
                if i * 20 + 1 > 240 then
                    break
                end
				frame.display.text(line, 1, i * 20 + 1, 0xFFFFFF)
			end
            i = i + 1
        end
    end
	if frame.HARDWARE_VERSION == "Frame" then
		frame.display.show()
	end
end

function clear_display()
	if frame.HARDWARE_VERSION == "Frame" then
		frame.display.text(" ", 1, 1)
		frame.display.show()
	else
		-- Halo
		frame.display.clear()
	end
end



-- Main app loop
function app_loop()
	if frame.HARDWARE_VERSION ~= "Frame" then
		frame.display.brightness(30)
	end

	-- clear the display
	clear_display()
    local last_batt_update = 0
    local caption = ''
    local drawing_image = false

    print("App started")

    while true do
        rc, err = pcall(
            function()
                -- process any raw items, if ready (parse into image or text, then clear raw)
                local items_ready = data.process_raw_items()

                -- only need to print it once when it's ready, it will stay there
                -- but if we print either, then we need to print both because a draw call and show
                -- will flip the buffer away from the already-drawn text/image
                if items_ready > 0 then
                    if (data.app_data[TEXT_FLAG] ~= nil and data.app_data[TEXT_FLAG].string ~= nil) then
                        -- save the string here and we'll print it before show()
                        caption = data.app_data[TEXT_FLAG].string

                        -- if we have a new caption, clear the display on Halo
                        if not drawing_image and frame.HARDWARE_VERSION ~= "Frame" then
                            clear_display()
                        end
                    end

                    if (data.app_data[IMAGE_SPRITE_BLOCK] ~= nil) then
                        -- first time we are drawing an image, clear the display on Halo. Frame keeps the text
                        if not drawing_image and frame.HARDWARE_VERSION ~= "Frame" then
                            drawing_image = true
                            clear_display()
                        end

                        -- show the image sprite block
                        local isb = data.app_data[IMAGE_SPRITE_BLOCK]

                        -- it can be that we haven't got any sprites yet, so only proceed if we have a sprite
                        if isb.current_sprite_index > 0 then
                            -- either we have all the sprites, or we want to do progressive/incremental rendering
                            if isb.progressive_render or (isb.active_sprites == isb.total_sprites) then

								for index = 1, isb.active_sprites do
									local spr = isb.sprites[index]
									local y_offset = isb.sprite_line_height * (index - 1)

									if frame.HARDWARE_VERSION == 'Frame' then
										-- set the palette the first time, all the sprites should have the same palette
										if index == 1 then
											image_sprite_block.set_palette(spr.num_colors, spr.palette_data)
										end

										frame.display.bitmap(1, y_offset + 1, spr.width, 2^spr.bpp, 0, spr.pixel_data)
									else
										frame.display.bitmap(1, y_offset + 1, spr.width, 2^spr.bpp, 0, spr.pixel_data, {palette_data=spr.palette_data})
									end
								end
								if frame.HARDWARE_VERSION == 'Frame' then
									frame.display.show()
								end
                            end

                            if isb.active_sprites == isb.total_sprites then
                                -- all done, clear the data so we don't keep re-drawing it
                                data.app_data[IMAGE_SPRITE_BLOCK] = nil
                                drawing_image = false

                                -- also make sure there is no caption to draw now that drawing_image is false
                                if frame.HARDWARE_VERSION ~= "Frame" then
                                    caption = ''
                                end
                            end
                        end
                    end

                    -- always show the current caption if there is one on Frame, 
                    -- only show a caption when not drawing an image on Halo
                    if caption ~= '' then
                        if frame.HARDWARE_VERSION == 'Frame' or not drawing_image then
                            print_text(caption)
                        end
                    end
                end

                -- TODO tune sleep durations to optimise for data handler and processing
                frame.sleep(0.005)

                -- periodic battery level updates
				if frame.HARDWARE_VERSION == "Frame" then
                	last_batt_update = battery.send_batt_if_elapsed(last_batt_update, 180)
                end
                -- TODO clear display after an amount of time?
            end
        )
        -- Catch the break signal here and clean up the display
        if rc == false then
            -- send the error back on the stdout stream
            print(err)
            clear_display()
            frame.sleep(0.04)
            break
        end
    end
end

-- run the main app loop
app_loop()