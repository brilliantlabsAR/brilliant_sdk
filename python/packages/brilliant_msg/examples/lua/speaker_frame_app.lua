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
	frame.display.text('App Started', 1, 1)
	frame.display.show() -- no-op on Halo

	-- tell the host program that the frameside app is ready (waiting on await_print)
	print('App Started')

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
						if frame.HARDWARE_VERSION ~= 'Frame' then
							if msg.value == 1 then
								print("Starting speaker")
								frame.speaker.start{encoder='lc3', sample_rate=8000, duration=1000, channels=1, bitrate=32000, volume=50}
							else
								print("Stopping speaker")
								frame.speaker.stop()
							end
						else
							frame.display.text('Speaker not available on Frame', 1, 1)
							frame.display.show()
						end
						collectgarbage('collect')
					end
				end

				-- sleep and wake up often enough for control messages
				frame.sleep(0.1)
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