local data = require('data.min')
local code = require('code.min')
local imu = require('imu.min')

-- Phone to Frame flags
IMU_SUBS_MSG = 0x40

-- Frame to Phone flags
IMU_DATA_MSG = 0x0A

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
	frame.display.power_save(false)
	clear_display()
	frame.display.text('Frame App Started', 50, 50)
	frame.display.show()

	local streaming = false

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

					if flag == IMU_SUBS_MSG then
						local msg = code.parse_code(raw)
						if msg.value == 1 then
							-- start subscription to IMU
							streaming = true
							if (frame.HARDWARE_VERSION ~= 'Frame') then
								frame.display.clear()
							end
							frame.display.text('Streaming IMU', 50, 50)
							frame.display.show()
						else
							-- cancel subscription to IMU
							streaming = false
							if (frame.HARDWARE_VERSION ~= 'Frame') then
								frame.display.clear()
							end
							frame.display.text('Not streaming IMU', 50, 50)
							frame.display.show()
						end
					end
				end

				-- poll and send the raw IMU data (3-axis magnetometer, 3-axis accelerometer)
				-- Streams until STOP_IMU_MSG is sent from host
				if streaming then
					imu.send_imu_data(IMU_DATA_MSG)
				end

				frame.sleep(0.2)
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