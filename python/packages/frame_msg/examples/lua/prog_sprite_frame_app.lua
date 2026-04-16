local data = require('data.min')
local image_sprite_block = require('image_sprite_block.min')

-- Phone to Frame flags
IMAGE_SPRITE_BLOCK = 0x20

-- draw the specified text on the display
function print_text(text)
    local i = 0
    for line in text:gmatch('([^\n]*)\n?') do
        if line ~= "" then
            frame.display.text(line, 1, i * 60 + 1)
            i = i + 1
        end
    end
	if frame.HARDWARE_VERSION == 'Frame' then
		frame.display.show()
	end
end

function clear_display()
	if frame.HARDWARE_VERSION == 'Frame' then
		frame.display.text(' ', 1, 1)
		frame.display.show()
	else
		frame.display.clear()
	end
end

-- Main app loop
function app_loop()
	if frame.HARDWARE_VERSION ~= 'Frame' then
		frame.display.power_save(false)
		frame.display.set_brightness(-2)
	end

	print('Frame App Started')
	clear_display()

	-- accumulator for image sprite block (persists across loop iterations)
	local isb = nil

	while true do
        rc, err = pcall(
            function()
				-- process any raw data items, if ready
				local items = data.process_raw_items()

				for i = 1, #items do
					local flag = items[i][1]
					local raw = items[i][2]

					if flag == IMAGE_SPRITE_BLOCK then
						isb = image_sprite_block.parse_image_sprite_block(raw, isb)

						-- it can be that we haven't got any sprites yet, so only proceed if we have a sprite
						if isb ~= nil and isb.current_sprite_index > 0 then
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
						end
					end
				end

				frame.sleep(0.01)
			end
		)
		-- Catch an error (including the break signal) here
		if rc == false then
			-- send the error back on the stdout stream and clear the display
			print(err)
			clear_display()
			break
		end
	end
end

-- run the main app loop
app_loop()