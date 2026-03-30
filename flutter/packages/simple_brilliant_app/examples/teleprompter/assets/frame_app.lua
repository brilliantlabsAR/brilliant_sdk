local data = require('data.min')
local battery = require('battery.min')
local sprite = require('sprite.min')
local code = require('code.min')
local text_sprite_block = require('text_sprite_block')

-- Phone to Frame flags
TEXT_SPRITE_BLOCK = 0x20
CLEAR_MSG = 0x10

-- message parsers, keyed by message flag
local parsers = {}
parsers[TEXT_SPRITE_BLOCK] = text_sprite_block.parse_text_sprite_block
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
	end

    print('Frame App Started')

	-- message handlers, dispatched in arrival order by the main loop
	local handlers = {}

	handlers[TEXT_SPRITE_BLOCK] = function(tsb)
		-- it can be that we haven't got any sprites yet
		local shift_y = 0
		if #tsb.sprites > 0 then
			for index = 1, #tsb.sprites do
				local spr = tsb.sprites[index]
				frame.display.bitmap(1, 1 + (index - 1)*spr.height, spr.width, 2^spr.bpp, 0, spr.pixel_data)
			end

			if frame.HARDWARE_VERSION == 'Frame' then
				frame.display.show()
			end
			last_text_show = frame.time.utc()
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
                frame.sleep(0.05)
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