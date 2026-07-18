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

-- message parsers, keyed by message flag
local parsers = {}
parsers[TEXT_MSG] = plain_text.parse_plain_text
parsers[CLEAR_MSG] = code.parse_code
parsers[START_IMU_MSG] = code.parse_code
parsers[STOP_IMU_MSG] = code.parse_code

-- Clear the whole display.
-- Frame presents a fresh buffer on every show(), so drawing a space + show()
-- wipes the previous frame; Halo draws immediately and needs an explicit
-- frame.display.clear() (the space trick is a no-op there and content overdraws).
function clear_display()
	if frame.HARDWARE_VERSION == 'Frame' then
		frame.display.text(" ", 1, 1)
		frame.display.show()
	else
		frame.display.clear()
	end
end

-- Main app loop
function app_loop()
	clear_display()
    local last_batt_update = 0
	local streaming = false
	local stream_rate = 1

	-- message handlers, dispatched in arrival order by the main loop
	local handlers = {}

	handlers[TEXT_MSG] = function(item)
		if item.string ~= nil then
			-- clear first so successive updates replace rather than overdraw on Halo
			if frame.HARDWARE_VERSION ~= 'Frame' then
				frame.display.clear()
			end
			local i = 0
			for line in item.string:gmatch("([^\n]*)\n?") do
				if line ~= "" then
					frame.display.text(line, 1, i * 60 + 1)
					i = i + 1
				end
			end
			frame.display.show()
		end
	end

	handlers[CLEAR_MSG] = function(item)
		clear_display()
	end

	handlers[START_IMU_MSG] = function(item)
		streaming = true
		local rate = item.value
		if rate > 0 then
			stream_rate = 1 / rate
		end
		-- clear first so this replaces the previous screen rather than overdrawing on Halo
		if frame.HARDWARE_VERSION ~= 'Frame' then
			frame.display.clear()
		end
		frame.display.text("Streaming IMU Data", 1, 1)
		frame.display.show()
	end

	handlers[STOP_IMU_MSG] = function(item)
		streaming = false
		clear_display()
	end

	while true do
		-- drain the message queue, parse and dispatch in arrival order
		local items = data.process_raw_items()

		for i = 1, #items do
			local flag = items[i][1]
			local raw  = items[i][2]

			if parsers[flag] == nil then
				print('Error: No parser for flag: ' .. tostring(flag))
			else
				local parsed = parsers[flag](raw)

				if handlers[flag] ~= nil then
					handlers[flag](parsed)
				else
					print('Error: No handler for flag: ' .. tostring(flag))
				end
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