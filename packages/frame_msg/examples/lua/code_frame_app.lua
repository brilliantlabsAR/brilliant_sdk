local data = require('data.min')
local code = require('code.min')

-- Phone to Frame flags
USER_CODE_FLAG = 0x42

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[USER_CODE_FLAG] = code.parse_code

-- Main app loop
function app_loop()
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
				local items_ready = data.process_raw_items()

				-- one or more full messages received
				if items_ready > 0 then

					if data.app_data[USER_CODE_FLAG] ~= nil then
						local code = data.app_data[USER_CODE_FLAG]
						if frame.HARDWARE_VERSION == 'Frame' then
							frame.display.text('Code received: ' .. tostring(code.value), 1, 1)
							frame.display.show()
						else
							frame.display.text('Code received: ' .. tostring(code.value), 50, 50, 0xFFFFFF)
						end

						-- clear the object and run the garbage collector right away
						data.app_data[USER_CODE_FLAG] = nil
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
			if frame.HARDWARE_VERSION == 'Frame' then
				frame.display.text(' ', 1, 1)
				frame.display.show()
			else
				frame.display.clear(0x000000)
			end
			break
		end
	end
end

-- run the main app loop
app_loop()