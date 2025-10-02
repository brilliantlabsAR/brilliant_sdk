local data = require('data.min')
local battery = require('battery.min')
local code = require('code.min')
local sprite = require('sprite.min')

-- Phone to Frame flags
SPRITE_1 = 0x21
SPRITE_2 = 0x22
SPRITE_3 = 0x23
SPRITE_TEXT_1 = 0x31
SPRITE_TEXT_2 = 0x32
SPRITE_TEXT_3 = 0x33
CLEAR_MSG = 0x10
NEXT_MSG = 0x11

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[SPRITE_1] = sprite.parse_sprite
data.parsers[SPRITE_2] = sprite.parse_sprite
data.parsers[SPRITE_3] = sprite.parse_sprite
data.parsers[SPRITE_TEXT_1] = sprite.parse_sprite
data.parsers[SPRITE_TEXT_2] = sprite.parse_sprite
data.parsers[SPRITE_TEXT_3] = sprite.parse_sprite
data.parsers[CLEAR_MSG] = code.parse_code
data.parsers[NEXT_MSG] = code.parse_code

function clear_display()
    if frame.HARDWARE_VERSION == 'Frame' then
		frame.display.text(' ', 1, 1)
		frame.display.show()
	else
		frame.display.clear(0x18309C)
	end
end

-- Main app loop
function app_loop()
	clear_display()
    local last_batt_update = 0
	local all_sprites = {}

	if frame.HARDWARE_VERSION ~= 'Frame' then
		frame.display.set_brightness(50)
		-- special background color for this animation
		frame.display.clear(0x18309C)
	end

    print('Frame App Started')

	while true do
		rc, err = pcall(
            function()
				-- process any raw data items, if ready
				local items_ready = data.process_raw_items()

				-- one or more full messages received
				if items_ready > 0 then

					-- do we have all the sprites?
					if (data.app_data[SPRITE_1] ~= nil and 
						data.app_data[SPRITE_TEXT_1] ~= nil and 
						data.app_data[SPRITE_2] ~= nil and 
						data.app_data[SPRITE_TEXT_2] ~= nil and 
						data.app_data[SPRITE_3] ~= nil and
						data.app_data[SPRITE_TEXT_3] ~= nil 
					) then
						print('All sprites received')
						all_sprites = {
							data.app_data[SPRITE_1], 
							data.app_data[SPRITE_TEXT_1],
							data.app_data[SPRITE_2], 
							data.app_data[SPRITE_TEXT_2],
							data.app_data[SPRITE_3],
							data.app_data[SPRITE_TEXT_3]
						}
						data.app_data[SPRITE_1] = nil
						data.app_data[SPRITE_2] = nil
						data.app_data[SPRITE_3] = nil
						data.app_data[SPRITE_TEXT_1] = nil
						data.app_data[SPRITE_TEXT_2] = nil
						data.app_data[SPRITE_TEXT_3] = nil
					end

					if (data.app_data[NEXT_MSG] ~= nil) then
						print('Next sprite message received')
						-- display the next sprite in the sequence
						if #all_sprites > 0 then
							print('Displaying next sprite')
							local spr = table.remove(all_sprites, 1)
							table.insert(all_sprites, spr)
							local spr_text = table.remove(all_sprites, 1)
							table.insert(all_sprites, spr_text)

							-- clear just the display area
							--print(#spr.pixel_data*8/spr.bpp/(spr.width+7//8))
							--frame.display.bitmap(101, 71, 1, 2, 0, '\xFF', {palette_data='\x000000\x18309C', x_scale=spr.width, y_scale=#spr.pixel_data*8/spr.bpp/(spr.width+7//8)})
							--frame.display.bitmap(101, 71, 1, 2, 0, '\xFF', {palette_data='\x00\x00\x00\x18\x30\x9C', x_scale=1, y_scale=spr.height//8})

							-- draw the sprite
							frame.display.clear(0x18309C)
							-- 120x60 @ 101,71
							frame.display.bitmap(101, 71, spr.width, 2^spr.bpp, 0, spr.pixel_data, {palette_data=spr.palette_data})
							-- 140x30 @ 91,136
							frame.display.bitmap(91, 136, spr_text.width, 2^spr_text.bpp, 0, spr_text.pixel_data, {palette_data=spr_text.palette_data})
						end
						data.app_data[NEXT_MSG] = nil
					end

					if (data.app_data[CLEAR_MSG] ~= nil) then
						-- clear the display
						print('Clear display message received')
						clear_display()
						data.app_data[CLEAR_MSG] = nil
					end
				end

				-- can't sleep for long, might be lots of incoming bluetooth data to process
				frame.sleep(0.001)
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