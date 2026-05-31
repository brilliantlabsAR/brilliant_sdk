local data = require('data.min')
local battery = require('battery.min')
local camera = require('camera.min')
local code = require('code.min')
local plain_text = require('plain_text.min')

-- Phone to Frame flags
CAPTURE_SETTINGS_MSG = 0x0d
AUTO_EXP_SETTINGS_MSG = 0x0e
MANUAL_EXP_SETTINGS_MSG = 0x0f
TEXT_MSG = 0x0a
TAP_SUBS_MSG = 0x10

-- Frame to Host flags
TAP_MSG = 0x09
AUTO_EXP_MSG = 0x12

function handle_tap()
	rc, err = pcall(frame.bluetooth.send, string.char(TAP_MSG))

	if rc == false then
		-- send the error back on the stdout stream
		print(err)
	end

end

-- draw the current text on the display
function print_text(parsed)
    local i = 0
    for line in parsed.string:gmatch("([^\n]*)\n?") do
        if line ~= "" then
            frame.display.text(line, 1, i * 60 + 1)
            i = i + 1
        end
    end
end

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
    local last_batt_update = 0

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

					elseif flag == AUTO_EXP_SETTINGS_MSG then
						rc, err = pcall(camera.set_auto_exp_settings, camera.parse_auto_exp_settings(raw))

						if rc == false then
							print(err)
						end

					elseif flag == MANUAL_EXP_SETTINGS_MSG then
						rc, err = pcall(camera.set_manual_exp_settings, camera.parse_manual_exp_settings(raw))

						if rc == false then
							print(err)
						end

					elseif flag == TEXT_MSG then
						local parsed = plain_text.parse_plain_text(raw)
						if parsed ~= nil and parsed.string ~= nil then
							print_text(parsed)
							frame.display.show()
						end

					elseif flag == TAP_SUBS_MSG then
						local msg = code.parse_code(raw)
						if msg.value == 1 then
							-- start subscription to tap events
							print('subscribing for taps')
							frame.imu.tap_callback(handle_tap)
						else
							-- cancel subscription to tap events
							print('cancel subscription for taps')
							frame.imu.tap_callback(nil)
						end
					end
				end

				-- periodic battery level updates, 120s for a camera app
				last_batt_update = battery.send_batt_if_elapsed(last_batt_update, 120)

				if camera.is_auto_exp then
					autoexp_result = camera.run_auto_exposure()
					-- send the current auto exposure result back to the host
					camera.send_autoexp_result(autoexp_result)
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