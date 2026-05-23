local data = require('data.min')
local plain_text = require('plain_text.min')

-- Phone to Frame msg codes
TEXT_MSG = 0x0a

-- draw the specified text on the display
function print_text(text)
    local i = 0
    for line in text.string:gmatch('([^\n]*)\n?') do
        if line ~= "" then
            if frame.HARDWARE_VERSION == 'Frame' then
                frame.display.text(line, text.x, i * 60 + text.y, {color=text.color})
            else
                frame.display.text(line, text.x, i * 60 + text.y, text.color)
            end
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

	if frame.HARDWARE_VERSION == 'Frame' then
		frame.display.text('Frame App Started', 1, 1)
		frame.display.show()
	else
		frame.display.clear()
		frame.display.text('Frame App Started', 50, 50)
	end

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

					if flag == TEXT_MSG then
						local text = plain_text.parse_plain_text(raw)
						if text ~= nil and text.string ~= nil then
							clear_display()
							print_text(text)
							collectgarbage('collect')
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
