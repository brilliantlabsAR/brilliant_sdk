local data = require('data.min')
local battery = require('battery.min')
local code = require('code.min')
local image_sprite_block = require('image_sprite_block.min')

-- Phone to Frame flags
IMAGE_SPRITE_BLOCK = 0x20
CLEAR_MSG = 0x10

-- message parsers, keyed by message flag
local parsers = {}
parsers[IMAGE_SPRITE_BLOCK] = image_sprite_block.parse_image_sprite_block
parsers[CLEAR_MSG] = code.parse_code

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
	clear_display()
    local last_batt_update = 0

    -- app-owned state for accumulating message types
    local state = {}

	if frame.HARDWARE_VERSION ~= 'Frame' then
		frame.display.brightness(50)
		frame.display.power_save(false)
	end

    print('Frame App Started')

	-- message handlers, dispatched in arrival order by the main loop
	local handlers = {}

	handlers[IMAGE_SPRITE_BLOCK] = function(isb)
		-- it can be that we haven't got any sprites yet, so only proceed if we have a sprite
		if isb.current_sprite_index > 0 then

			if frame.HARDWARE_VERSION == 'Frame' then
				-- horizontally centre the image
				local width = math.min(isb.width, 640)
				local x_offset = (640 - width) // 2 + 1
				print(string.format("width = %d, height = %d, x_offset = %d", isb.width, isb.height, x_offset))

				-- either we have all the sprites, or we want to do progressive/incremental rendering
				if isb.progressive_render or (isb.active_sprites == isb.total_sprites) then

					for index = 1, isb.active_sprites do
						local spr = isb.sprites[index]
						local y_offset = isb.sprite_line_height * (index - 1)

						-- set the palette the first time, all the sprites should have the same palette
						if index == 1 then
							image_sprite_block.set_palette(spr.num_colors, spr.palette_data)
						end

						frame.display.bitmap(x_offset, y_offset + 1, spr.width, 2^spr.bpp, 0, spr.pixel_data)
					end
					frame.display.show()
				end

			else -- Halo
				-- horizontally and vertically centre the image
				local width = math.min(isb.width, 256)
				local x_offset = (256 - width) // 2 + 1
				local height = math.min(isb.height, 256)
				local y_offset = (256 - height) // 2 + 1
				print(string.format("width = %d, height = %d, x_offset = %d, y_offset = %d", isb.width, isb.height, x_offset, y_offset))

				for index = 1, isb.active_sprites do
					local spr = isb.sprites[index]
					local y_offset_line = isb.sprite_line_height * (index - 1) + y_offset

					frame.display.bitmap(x_offset, y_offset_line + 1, spr.width, 2^spr.bpp, 0, spr.pixel_data, {palette_data=spr.palette_data})
				end
			end

		end
	end

	handlers[CLEAR_MSG] = function(item)
		clear_display()
	end

	while true do
		rc, err = pcall(
            function()
				-- drain the message queue, parse and dispatch in arrival order
				local items = data.process_raw_items()

				for i = 1, #items do
					local flag = items[i][1]
					local raw  = items[i][2]

					if parsers[flag] == nil then
						print('Error: No parser for flag: ' .. tostring(flag))
					else
						local parsed

						-- accumulating types: need to pass previous state to the parser
						if flag == TEXT_SPRITE_BLOCK then
							parsed = parsers[flag](raw, state[flag])
							state[flag] = parsed
						else
							parsed = parsers[flag](raw)
						end

						if handlers[flag] ~= nil then
							handlers[flag](parsed)
						else
							print('Error: No handler for flag: ' .. tostring(flag))
						end
					end
				end

				-- periodic battery level updates
				last_batt_update = battery.send_batt_if_elapsed(last_batt_update, 120)
				-- can't sleep for long, might be lots of incoming bluetooth data to process
				frame.sleep(0.01)
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

