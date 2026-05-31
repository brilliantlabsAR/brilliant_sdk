local data = require('data.min')
local camera = require('camera.min')
local image_sprite_block = require('image_sprite_block.min')

-- Phone to Frame flags
CAPTURE_SETTINGS_MSG = 0x0d
IMAGE_SPRITE_BLOCK = 0x20

function clear_display()
	if frame.HARDWARE_VERSION == 'Frame' then
		frame.display.text(' ', 1, 1)
		frame.display.show()
	else
		frame.display.clear()
	end
end

function show_flash()
    frame.display.bitmap(241, 191, 160, 2, 0, string.rep("\xFF", 400))
    frame.display.bitmap(311, 121, 20, 2, 0, string.rep("\xFF", 400))
    frame.display.show()
    frame.sleep(0.04)
end

-- Main app loop
function app_loop()
	clear_display()

	-- tell the host program that the frameside app is ready (waiting on await_print)
	print('Frame app is running')

	frame.camera.power_save(false)
	frame.display.power_save(false)
	local new_image = true
	local drawn_index = 0

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

					if flag == CAPTURE_SETTINGS_MSG then
						rc, err = pcall(camera.capture_and_send, camera.parse_capture_settings(raw))

						if rc == false then
							print(err)
						end

					elseif flag == IMAGE_SPRITE_BLOCK then
						isb = image_sprite_block.parse_image_sprite_block(raw, isb)

						-- it can be that we haven't got any sprites yet, so only proceed if we have a sprite
						if isb ~= nil and isb.current_sprite_index > 0 then
							-- either we have all the sprites, or we want to do progressive/incremental rendering
							if isb.progressive_render or (isb.active_sprites == isb.total_sprites) then

								-- on Frame, each draw call starts blank, so draw all sprites 1..n
								if frame.HARDWARE_VERSION == 'Frame' then

									for index = 1, isb.active_sprites do
										local spr = isb.sprites[index]
										local y_offset = isb.sprite_line_height * (index - 1)

										-- set the palette the first time, all the sprites should have the same palette
										if index == 1 then
											image_sprite_block.set_palette(spr.num_colors, spr.palette_data)
										end

										frame.display.bitmap(1, y_offset + 1, spr.width, 2^spr.bpp, 0, spr.pixel_data)
									end
									frame.display.show()

									if isb.active_sprites == isb.total_sprites then
										isb = nil
									end
								else
									if new_image then
										-- clear the display first, Halo doesn't automatically clear
										frame.display.clear()
										new_image = false
									end

									-- On Halo, draw calls are additive, so just draw the latest sprite(s)
									for index = drawn_index + 1, isb.active_sprites do
										local spr = isb.sprites[index]
										local y_offset = isb.sprite_line_height * (index - 1)

										if index == 1 then
											-- set the palette the first time, all the sprites should have the same palette
											image_sprite_block.set_palette(spr.num_colors, spr.palette_data)
										end

										frame.display.bitmap(1, y_offset + 1, spr.width, 2^spr.bpp, 0, spr.pixel_data)
										drawn_index = index

										if drawn_index == isb.total_sprites then
											isb = nil
											new_image = true
											drawn_index = 0
										end
									end
								end
							end
						end
					end
				end

				if frame.HARDWARE_VERSION == 'Frame' and camera.is_auto_exp then
					camera.run_auto_exposure()
				end

				frame.sleep(0.1)
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