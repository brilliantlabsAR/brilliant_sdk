local data = require('data.min')
local battery = require('battery.min')
local image_sprite_block = require('image_sprite_block.min')
local plain_text = require('plain_text.min')

-- Phone to Frame flags
TEXT_FLAG = 0x0a
IMAGE_SPRITE_BLOCK = 0x0d

-- message parsers, keyed by message flag
local parsers = {}
parsers[TEXT_FLAG] = plain_text.parse_plain_text
parsers[IMAGE_SPRITE_BLOCK] = image_sprite_block.parse_image_sprite_block

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

-- message handlers, dispatched in arrival order by the main loop
local handlers = {}

handlers[TEXT_FLAG] = function(parsed_data)
	if parsed_data.string ~= nil then
		-- save the string here and we'll print it before show()
		caption = parsed_data.string

		-- if we have a new caption, clear the display on Halo
		if not drawing_image and frame.HARDWARE_VERSION ~= "Frame" then
			clear_display()
		end
	end
end

handlers[IMAGE_SPRITE_BLOCK] = function(parsed_data)
	-- first time we are drawing an image, clear the display on Halo. Frame keeps the text
	if not drawing_image and frame.HARDWARE_VERSION ~= "Frame" then
		drawing_image = true
		clear_display()
	end

	-- show the image sprite block
	local isb = parsed_data

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
			drawing_image = false

			-- also make sure there is no caption to draw now that drawing_image is false
			if frame.HARDWARE_VERSION ~= "Frame" then
				caption = ''
			end
		end
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
                -- process any raw items, returns array of parsed items
                local items = data.process_raw_items()

                -- only need to print it once when it's ready, it will stay there
                -- but if we print either, then we need to print both because a draw call and show
                -- will flip the buffer away from the already-drawn text/image
                if #items > 0 then
                    for i = 1, #items do
                        local flag = items[i][1]
                        local raw = items[i][2]

                        if parsers[flag] then
                            local parsed = parsers[flag](raw)
                            if handlers[flag] then
                                handlers[flag](parsed)
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
