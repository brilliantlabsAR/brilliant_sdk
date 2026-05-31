local data = require('data.min')
local camera = require('camera.min')
local code = require('code.min')

-- Phone to Frame flags
CAPTURE_SETTINGS_MSG = 0x0d
MANUALEXP_SETTINGS_MSG = 0x0c

function clear_display()
	if frame.HARDWARE_VERSION == 'Frame' then
		frame.display.text(' ', 1, 1)
		frame.display.show()
	else
		frame.display.clear()
	end
end

function show_flash()
    frame.display.bitmap(241, 191, 160, 2, 0, string.rep("\xFF", 400))
    frame.display.bitmap(311, 121, 20, 2, 0, string.rep("\xFF", 400))
    frame.display.show()
    frame.sleep(0.04)
end

-- Main app loop
function app_loop()
	clear_display()

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

					if flag == CAPTURE_SETTINGS_MSG then
						-- visual indicator of capture and send
						show_flash()
						rc, err = pcall(camera.capture_and_send, camera.parse_capture_settings(raw))
						clear_display()

						if rc == false then
							print(err)
						end

					elseif flag == MANUALEXP_SETTINGS_MSG then
						camera.set_manual_exp_settings(camera.parse_manual_exp_settings(raw))
					end
				end

				frame.sleep(0.1)
			end
		)
		-- Catch the break signal here and clean up the display
		if rc == false then
			-- send the error back on the stdout stream
			print(err)
			frame.display.text(" ", 1, 1)
			frame.display.show()
			frame.sleep(0.04)
			break
		end
	end
end

-- run the main app loop
app_loop()