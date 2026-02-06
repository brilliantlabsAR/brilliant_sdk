local data = require('data.min')
local battery = require('battery.min')
local code = require('code.min')
local imu = require('imu.min')
local plain_text = require('plain_text.min')

-- Phone to Frame flags
TEXT_MSG = 0x12
CLEAR_MSG = 0x10
START_IMU_MSG = 0x40
STOP_IMU_MSG = 0x41

-- Frame to Phone flags
IMU_DATA_MSG = 0x0A

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[TEXT_MSG] = plain_text.parse_plain_text
data.parsers[CLEAR_MSG] = code.parse_code
data.parsers[START_IMU_MSG] = code.parse_code
data.parsers[STOP_IMU_MSG] = code.parse_code


-- Main app loop
function app_loop()
	-- clear the display
	frame.display.text(" ", 1, 1)
	frame.display.show()
    local last_batt_update = 0
	local streaming = false
	local stream_rate = 1

	while true do
		-- process any raw data items, if ready
		local items_ready = data.process_raw_items()

		-- one or more full messages received
		if items_ready > 0 then

			if (data.app_data[TEXT_MSG] ~= nil and data.app_data[TEXT_MSG].string ~= nil) then
				local i = 0
				for line in data.app_data[TEXT_MSG].string:gmatch("([^\n]*)\n?") do
					if line ~= "" then
						frame.display.text(line, 1, i * 60 + 1)
						i = i + 1
					end
				end
				frame.display.show()
			end

			if (data.app_data[CLEAR_MSG] ~= nil) then
				-- clear the display
				frame.display.text(" ", 1, 1)
				frame.display.show()

				data.app_data[CLEAR_MSG] = nil
			end

			if (data.app_data[START_IMU_MSG] ~= nil) then
				streaming = true
				local rate = data.app_data[START_IMU_MSG].value
				if rate > 0 then
					stream_rate = 1 / rate
				end
				frame.display.text("Streaming IMU Data", 1, 1)
				frame.display.show()

				data.app_data[START_IMU_MSG] = nil
			end

			if (data.app_data[STOP_IMU_MSG] ~= nil) then
				streaming = false
				-- clear the display
				frame.display.text(" ", 1, 1)
				frame.display.show()

				data.app_data[STOP_IMU_MSG] = nil
			end
		end

		-- poll and send the raw IMU data (3-axis magnetometer, 3-axis accelerometer)
		-- Streams until STOP_IMU_MSG is sent from phone
		if streaming then
			imu.send_imu_data(IMU_DATA_MSG)
		end

        -- periodic battery level updates, 120s for a camera app
        last_batt_update = battery.send_batt_if_elapsed(last_batt_update, 120)
		if streaming then
			frame.sleep(stream_rate)
		else
			frame.sleep(0.5)
		end
	end
end

-- run the main app loop
app_loop()