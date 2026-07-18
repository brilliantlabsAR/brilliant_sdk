-- IMU axis DIAGNOSTIC frame app.
--
-- Unlike imu.lua (which remaps/scales the Halo axes before sending), this app
-- streams the *native* frame.imu.raw() values with NO axis remap, NO sign flip
-- and NO scaling. The host imu_diagnostic.py uses this to independently determine
-- the correct device->host axis mapping and magnitudes.
--
-- Wire format (matches imu.lua so the host framing is unchanged):
--   msg_code (u8), 1 pad byte, then 6 little-endian float32:
--     compass.x, compass.y, compass.z, accelerometer.x, accelerometer.y, accelerometer.z

local data = require('data.min')
local code = require('code.min')

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

-- Pack and send the *native* raw IMU sample (no remap, no scale)
function send_native_imu(msg_code)
	local r = frame.imu.raw()
	local packed = string.pack("<Bxffffff", msg_code,
		r.compass.x, r.compass.y, r.compass.z,
		r.accelerometer.x, r.accelerometer.y, r.accelerometer.z)
	pcall(frame.bluetooth.send, packed)
end

-- Main app loop
function app_loop()
	frame.display.power_save(false)
	clear_display()
	frame.display.text('IMU Diagnostic', 50, 50)
	frame.display.show()

	local streaming = false

	-- tell the host program that the frameside app is ready (waiting on await_print)
	print('IMU diagnostic app is running')

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
						streaming = (msg.value ~= 0)
						if frame.HARDWARE_VERSION ~= 'Frame' then
							frame.display.clear()
						end
						frame.display.text(streaming and 'Streaming native IMU' or 'Stopped', 50, 50)
						frame.display.show()
					end
				end

				-- poll and send the *native* raw IMU sample
				if streaming then
					send_native_imu(IMU_DATA_MSG)
				end

				frame.sleep(0.05)
			end
		)
		-- Catch an error (including the break signal) here
		if rc == false then
			print(err)
			clear_display()
			break
		end
	end
end

-- run the main app loop
app_loop()
