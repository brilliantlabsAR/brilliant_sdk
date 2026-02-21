local data = require('data.min')
local code = require('code.min')
local text_sprite_block = require('text_sprite_block.min')

-- Phone to Frame flags
TEXT_SPRITE_BLOCK = 0x20
RESET_TEXT_BLOCK = 0x21

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[TEXT_SPRITE_BLOCK] = text_sprite_block.parse_text_sprite_block
data.parsers[RESET_TEXT_BLOCK] = code.parse_code

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

	while true do
        rc, err = pcall(
            function()
				-- process any raw data items, if ready
				local items_ready = data.process_raw_items()

				-- one or more full messages received
				if items_ready > 0 then

					if (data.app_data[RESET_TEXT_BLOCK] ~= nil) then
						clear_display()

						if data.app_data[TEXT_SPRITE_BLOCK] ~= nil then
							-- also clear any existing text sprite block data
							tsb = data.app_data[TEXT_SPRITE_BLOCK]
							for k in pairs(tsb.sprites) do tsb[k] = nil end
							data.app_data[TEXT_SPRITE_BLOCK] = nil
							collectgarbage()
						end
						data.app_data[RESET_TEXT_BLOCK] = nil
					end

					if (data.app_data[TEXT_SPRITE_BLOCK] ~= nil) then
						-- show the text sprite block
						local tsb = data.app_data[TEXT_SPRITE_BLOCK]
						--print('Received text sprite block with line_height=' .. tostring(tsb.line_height) .. ' and width=' .. tostring(tsb.width))

						-- it can be that we haven't got any sprites yet, so only proceed if we have a sprite
						if #tsb.sprites > 0 then
							if frame.HARDWARE_VERSION ~= 'Frame' then
								-- clear a rect the size of the text block to erase any previous text
								frame.display.rect(0, 0, tsb.width, tsb.max_display_lines * tsb.line_height, 0x000000, true)
							end

							for index, spr in ipairs(tsb.sprites) do
								local y_offset = tsb.line_height * (index-1) + 1
								--print('Drawing sprite index ' .. tostring(index) .. ' at y=' .. tostring(y_offset) .. ' spr.width=' .. tostring(spr.width) .. ' spr.height=' .. tostring(spr.height) .. ' bpp=' .. tostring(spr.bpp) .. ' num_colors=' .. tostring(2^spr.bpp))
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