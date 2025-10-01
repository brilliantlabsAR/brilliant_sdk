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
CLICK_SUBS_MSG = 0x11

-- register the message parser so it's automatically called when matching data comes in
data.parsers[CAPTURE_SETTINGS_MSG] = camera.parse_capture_settings
data.parsers[AUTO_EXP_SETTINGS_MSG] = camera.parse_auto_exp_settings
data.parsers[MANUAL_EXP_SETTINGS_MSG] = camera.parse_manual_exp_settings
data.parsers[TEXT_MSG] = plain_text.parse_plain_text
data.parsers[TAP_SUBS_MSG] = code.parse_code
data.parsers[CLICK_SUBS_MSG] = code.parse_code

-- Frame to Phone flags
TAP_MSG = 0x09
CLICK_MSG = 0x06

function handle_tap()
	rc, err = pcall(frame.bluetooth.send, string.char(TAP_MSG))

	if rc == false then
		-- send the error back on the stdout stream
		print(err)
	end

end

-- single (1), double (2), long (3)
function handle_click(type)
	rc, err = pcall(frame.bluetooth.send, string.char(CLICK_MSG) .. string.char(type))

	if rc == false then
		-- send the error back on the stdout stream
		print(err)
	end
end

-- draw the current text on the display
function print_text()
    local i = 0
    for line in data.app_data[TEXT_MSG].string:gmatch("([^\n]*)\n?") do
        if line ~= "" then
			if frame.HARDWARE_VERSION == "Frame" then
				frame.display.text(line, 1, i * 60 + 1)
			else
				frame.display.text(line, 1, i * 60 + 1, 0xFFFFFF)
			end
            i = i + 1
        end
    end
	if frame.HARDWARE_VERSION == "Frame" then
		frame.display.show()
	end
end

function clear_display()
	if frame.HARDWARE_VERSION == "Frame" then
		frame.display.text(" ", 1, 1)
		frame.display.show()
	else
		-- Halo
		frame.display.clear(0x000000)
	end
end

function show_flash()
	if frame.HARDWARE_VERSION == "Frame" then
		frame.display.bitmap(241, 191, 160, 2, 0, string.rep("\xFF", 400))
		frame.display.bitmap(311, 121, 20, 2, 0, string.rep("\xFF", 400))
		frame.display.show()
		frame.sleep(0.04)
	--else
		-- TODO for Halo
	end
end

-- Main app loop
function app_loop()
	clear_display()
    local last_batt_update = 0
	if frame.HARDWARE_VERSION ~= "Frame" then
		frame.camera.power_save(false)
	end
	print("Frame app started")

	while true do
        rc, err = pcall(
            function()
				-- process any raw data items, if ready (parse into take_photo, then clear data.app_data_block)
				local items_ready = data.process_raw_items()

				if items_ready > 0 then

					if (data.app_data[CAPTURE_SETTINGS_MSG] ~= nil) then
						-- visual indicator of capture and send
						show_flash()
						local rc, err
						if frame.HARDWARE_VERSION == "Frame" then
							rc, err = pcall(camera.capture_and_send, data.app_data[CAPTURE_SETTINGS_MSG])
						else
							rc, err = pcall(camera.capture_and_send, {resolution = 640, quality = data.app_data[CAPTURE_SETTINGS_MSG].quality})
						end
						clear_display()

						if rc == false then
							print(err)
						end

						data.app_data[CAPTURE_SETTINGS_MSG] = nil
					end

					if (data.app_data[AUTO_EXP_SETTINGS_MSG] ~= nil) then
						if frame.HARDWARE_VERSION == "Frame" then
							rc, err = pcall(camera.set_auto_exp_settings, data.app_data[AUTO_EXP_SETTINGS_MSG])

							if rc == false then
								print(err)
							end
						end

						data.app_data[AUTO_EXP_SETTINGS_MSG] = nil
					end

					if (data.app_data[MANUAL_EXP_SETTINGS_MSG] ~= nil) then
						if frame.HARDWARE_VERSION == "Frame" then
							rc, err = pcall(camera.set_manual_exp_settings, data.app_data[MANUAL_EXP_SETTINGS_MSG])

							if rc == false then
								print(err)
							end
						end

						data.app_data[MANUAL_EXP_SETTINGS_MSG] = nil
					end

					if (data.app_data[TEXT_MSG] ~= nil and data.app_data[TEXT_MSG].string ~= nil) then
						print_text()

						data.app_data[TEXT_MSG] = nil
					end

					if (data.app_data[TAP_SUBS_MSG] ~= nil) then

						if data.app_data[TAP_SUBS_MSG].value == 1 then
							-- start subscription to tap events
							print('subscribing for taps')
							frame.imu.tap_callback(handle_tap)
						else
							-- cancel subscription to tap events
							print('cancel subscription for taps')
							frame.imu.tap_callback(nil)
						end

						data.app_data[TAP_SUBS_MSG] = nil
					end

					if (data.app_data[CLICK_SUBS_MSG] ~= nil) then

						if data.app_data[CLICK_SUBS_MSG].value == 1 then
							-- start subscription to click events
							print('subscribing for clicks')
							frame.button.single(function() handle_click(1) end)
							frame.button.double(function() handle_click(2) end)
							frame.button.long(function() handle_click(3) end)
						else
							-- cancel subscription to click events
							print('cancel subscription for clicks')
							frame.button.single(nil)
							frame.button.double(nil)
							frame.button.long(nil)
						end

						data.app_data[CLICK_SUBS_MSG] = nil
					end

				end

				-- periodic battery level updates, 120s for a camera app
				if frame.HARDWARE_VERSION == "Frame" then
					last_batt_update = battery.send_batt_if_elapsed(last_batt_update, 120)

					if camera.is_auto_exp then
						camera.run_auto_exposure()
					end
				end

				frame.sleep(0.1)
			end
		)
		-- Catch the break signal here and clean up the display
		if rc == false then
			-- send the error back on the stdout stream
			print(err)
			clear_display()
			frame.sleep(0.04)
			break
		end
	end
end

-- run the main app loop
app_loop()