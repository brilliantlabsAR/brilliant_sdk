local data = require('data.min')
local sprite = require('sprite.min')
local code = require('code.min')
local sprite_coords = require('sprite_coords.min')

-- Phone to Frame flags
SPRITE_0 = 0x20
SPRITE_COORDS = 0x40
CODE_DRAW = 0x50

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[SPRITE_0] = sprite.parse_sprite
data.parsers[SPRITE_COORDS] = sprite_coords.parse_sprite_coords
data.parsers[CODE_DRAW] = code.parse_code

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
	end

	-- tell the host program that the frameside app is ready (waiting on await_print)
	print('Frame app is running')

	while true do
        rc, err = pcall(
            function()
				-- process any raw data items, if ready
				local items_ready = data.process_raw_items()

				-- one or more full messages received
				if items_ready > 0 then
					frame.sleep(0.1)

					-- sprite resource retained for later drawing
					if data.app_data[SPRITE_0] ~= nil then
						local spr = data.app_data[SPRITE_0]

						-- also updates Frame's palette to match the sprite
						if frame.HARDWARE_VERSION == 'Frame' then
							-- set Frame's palette to match the sprite in case it's different to the standard palette
							sprite.set_palette(spr.num_colors, spr.palette_data)

							collectgarbage('collect')
						end

						-- don't clear the sprite, we want to draw it later
					end

					-- place a sprite on the display (backbuffer)
					if data.app_data[SPRITE_COORDS] ~= nil then
						local coords = data.app_data[SPRITE_COORDS]
						local spr = data.app_data[coords.code]

						if spr ~= nil then
							if frame.HARDWARE_VERSION == 'Frame' then
								frame.display.bitmap(coords.x, coords.y, spr.width, spr.num_colors, coords.offset, spr.pixel_data)
							else
								frame.display.clear()
								frame.display.bitmap(coords.x, coords.y, spr.width, spr.num_colors, coords.offset, spr.pixel_data, {palette_data=spr.palette_data})
							end
						else
							print('Sprite not found: ' .. tostring(coords.code))
						end

						data.app_data[SPRITE_COORDS] = nil
					end


					-- flip the buffers, show what we've drawn
					if data.app_data[CODE_DRAW] ~= nil then
						data.app_data[CODE_DRAW] = nil

						frame.display.show()
					end

				end

				-- can't sleep for long, might be lots of incoming bluetooth data to process
				frame.sleep(0.001)
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