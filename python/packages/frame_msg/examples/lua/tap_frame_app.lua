local data = require('data.min')
local code = require('code.min')
local tap = require('tap.min')

-- Phone to Frame flags
TAP_SUBS_MSG = 0x10

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
	frame.display.text('Frame App Started', 50, 50)
	frame.display.show()

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

					if flag == TAP_SUBS_MSG then
						local msg = code.parse_code(raw)
						if msg.value == 1 then
							-- start subscription to tap events
							frame.imu.tap_callback(tap.send_tap)
							clear_display()
							frame.display.text('Listening for taps', 1, 1)
							frame.display.show()
						else
							-- cancel subscription to tap events
							frame.imu.tap_callback(nil)
							clear_display()
							frame.display.text('Not listening for taps', 1, 1)
							frame.display.show()
						end
					end
				end

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