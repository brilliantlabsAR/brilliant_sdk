local data = require('data.min')
local camera = require('camera.min')

-- Phone to Frame flags
CAPTURE_SETTINGS_MSG = 0x0d

-- register the message parser so it's automatically called when matching data comes in
data.parsers[CAPTURE_SETTINGS_MSG] = camera.parse_capture_settings

function clear_display()
	if frame.HARDWARE_VERSION == 'Frame' then
		frame.display.text(' ', 1, 1)
		frame.display.show()
	else
		frame.display.clear()
	end
end

function show_flash()
	if frame.HARDWARE_VERSION == 'Frame' then
		frame.display.bitmap(241, 191, 160, 2, 0, string.rep("\xFF", 400))
		frame.display.bitmap(311, 121, 20, 2, 0, string.rep("\xFF", 400))
		frame.display.show()
		frame.sleep(0.04)
	else
		frame.display.clear(0xFFFFFF)
		frame.display.clear(0x000000)
	end
end

-- Main app loop
function app_loop()
	clear_display()

	-- tell the host program that the frameside app is ready (waiting on await_print)
	print('Frame app is running')

	while true do
        rc, err = pcall(
            function()
				-- process any raw data items, if ready (parse into take_photo, then clear data.app_data_block)
				local items_ready = data.process_raw_items()

				if items_ready > 0 then

					if (data.app_data[CAPTURE_SETTINGS_MSG] ~= nil) then
						-- visual indicator of capture and send
						show_flash()
						rc, err = pcall(camera.capture_and_send, data.app_data[CAPTURE_SETTINGS_MSG])
						clear_display()

						if rc == false then
							print(err)
						end

						data.app_data[CAPTURE_SETTINGS_MSG] = nil
					end

				end

				if frame.HARDWARE_VERSION == 'Frame' and camera.is_auto_exp then
					camera.run_auto_exposure()
				end

				frame.sleep(0.1)
			end
		)
		-- Catch the break signal here and clean up the display
		if rc == false then
			-- send the error back on the stdout stream
			print(err)
			clear_display()
			break
		end
	end
end

-- run the main app loop
app_loop()