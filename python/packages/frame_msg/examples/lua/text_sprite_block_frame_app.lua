local data = require('data.min')
local code = require('code.min')
local text_sprite_block = require('text_sprite_block.min')

-- Phone to Frame flags
TEXT_SPRITE_BLOCK = 0x20
RESET_TEXT_BLOCK = 0x21

function clear_display()
	if frame.HARDWARE_VERSION ~= 'Frame' then
		frame.display.clear()
		frame.display.show()
	else
		frame.display.text(' ', 1, 1)
		frame.display.show()
	end
end

-- Main app loop
function app_loop()
	clear_display()
	frame.display.set_brightness(1)

	-- tell the host program that the frameside app is ready (waiting on await_print)
	print('Frame app is running')

	-- accumulator for text sprite block (persists across loop iterations)
	local current_tsb = nil

	while true do
        rc, err = pcall(
            function()
				-- process any raw data items, if ready
				local items = data.process_raw_items()

				for i = 1, #items do
					local flag = items[i][1]
					local raw = items[i][2]

					if flag == RESET_TEXT_BLOCK then
						clear_display()
						if current_tsb ~= nil then
							for k in pairs(current_tsb.sprites) do current_tsb.sprites[k] = nil end
							current_tsb = nil
							collectgarbage()
						end

					elseif flag == TEXT_SPRITE_BLOCK then
						current_tsb = text_sprite_block.parse_text_sprite_block(raw, current_tsb)

						-- show the text sprite block once we have sprites
						if current_tsb ~= nil and #current_tsb.sprites > 0 then
							if frame.HARDWARE_VERSION ~= 'Frame' then
								-- clear a rect the size of the text block to erase any previous text
								frame.display.rect(0, 0, current_tsb.width, current_tsb.max_display_lines * current_tsb.line_height, 0x000000, true)
							end

							for index, spr in ipairs(current_tsb.sprites) do
								local y_offset = current_tsb.line_height * (index-1) + 1
								frame.display.bitmap(1, y_offset, spr.width, 2^spr.bpp, 0+index-1, spr.pixel_data)
							end

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