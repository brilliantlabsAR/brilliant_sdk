local data = require('data.min')
local sprite = require('sprite.min')

-- Phone to Frame flags
USER_SPRITE = 0x20

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

	clear_display()
	print_text('Frame App Started')

	-- tell the host program that the frameside app is ready (waiting on await_print)
	print('Frame app is running')

	while true do
        rc, err = pcall(
            function()
				-- process any raw data items, if ready
				local items = data.process_raw_items()

				for i = 1, #items do
					local flag = items[i][1]
					local raw = items[i][2]

					if flag == USER_SPRITE then
						local spr = sprite.parse_sprite(raw)

						-- show the sprite
						if frame.HARDWARE_VERSION == 'Frame' then
							-- set the palette in case it's different to the standard palette
							sprite.set_palette(spr.num_colors, spr.palette_data)
							frame.display.bitmap(1, 1, spr.width, 2^spr.bpp, 0, spr.pixel_data)
							frame.display.show()
						else
							clear_display()
							frame.display.bitmap(1, 1, spr.width, 2^spr.bpp, 0, spr.pixel_data, {palette_data=spr.palette_data})
						end

						collectgarbage('collect')
					end
				end

				-- can't sleep for long, might be lots of incoming bluetooth data to process
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