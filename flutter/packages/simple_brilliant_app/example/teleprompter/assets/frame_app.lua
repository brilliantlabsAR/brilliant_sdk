local data = require('data.min')
local battery = require('battery.min')
local sprite = require('sprite.min')
local code = require('code.min')
local text_page = require('text_page.min')

-- Phone to Frame flags
TEXT_PAGE = 0x20
CLEAR_MSG = 0x10

-- message parsers, keyed by message flag
local parsers = {}
parsers[TEXT_PAGE] = text_page.parse_text_page
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

	handlers[TEXT_PAGE] = function(page)
		-- draw once every line of the page has arrived, each at its own x/y offset
		if text_page.is_complete(page) then
			text_page.draw(page)
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
						if flag == TEXT_PAGE then
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