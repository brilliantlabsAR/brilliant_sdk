local data = require('data.min')
local sprite = require('sprite.min')
local code = require('code.min')
local sprite_coords = require('sprite_coords.min')

-- Phone to Frame flags
SPRITE_0 = 0x20
SPRITE_COORDS = 0x40
CODE_DRAW = 0x50

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

	-- retained sprite resources, keyed by flag code
	local sprites = {}

	while true do
        rc, err = pcall(
            function()
				-- process any raw data items, if ready
				local items = data.process_raw_items()

				if #items > 0 then
					frame.sleep(0.1)

					for i = 1, #items do
						local flag = items[i][1]
						local raw = items[i][2]

						if flag == SPRITE_0 then
							-- sprite resource retained for later drawing
							sprites[SPRITE_0] = sprite.parse_sprite(raw)

							-- also updates Frame's palette to match the sprite
							if frame.HARDWARE_VERSION == 'Frame' then
								sprite.set_palette(sprites[SPRITE_0].num_colors, sprites[SPRITE_0].palette_data)
								collectgarbage('collect')
							end
							-- don't clear, we want to draw it later

						elseif flag == SPRITE_COORDS then
							-- place a sprite on the display (backbuffer)
							local coords = sprite_coords.parse_sprite_coords(raw)
							local spr = sprites[coords.code]

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

						elseif flag == CODE_DRAW then
							-- flip the buffers, show what we've drawn
							frame.display.show()
						end
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