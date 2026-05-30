local data = require('data.min')
local code = require('code.min')

-- Phone to Frame flags
USER_CODE_FLAG = 0x42

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
	if frame.HARDWARE_VERSION == 'Frame' then
		frame.display.text('Frame App Started', 1, 1)
		frame.display.show()
	else
		frame.display.text('Frame App Started', 50, 50, 0xFFFFFF)
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

					if flag == USER_CODE_FLAG then
						local msg = code.parse_code(raw)
						if frame.HARDWARE_VERSION == 'Frame' then
							frame.display.text('Code received: ' .. tostring(msg.value), 1, 1)
							frame.display.show()
						else
							frame.display.text('Code received: ' .. tostring(msg.value), 50, 50, 0xFFFFFF)
						end
						collectgarbage('collect')
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