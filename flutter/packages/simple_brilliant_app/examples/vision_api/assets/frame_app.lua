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

-- Frame to Phone flags
TAP_MSG = 0x09
CLICK_MSG = 0x06

-- message parsers, keyed by message flag
local parsers = {}
parsers[CAPTURE_SETTINGS_MSG] = camera.parse_capture_settings
parsers[AUTO_EXP_SETTINGS_MSG] = camera.parse_auto_exp_settings
parsers[MANUAL_EXP_SETTINGS_MSG] = camera.parse_manual_exp_settings
parsers[TEXT_MSG] = plain_text.parse_plain_text
parsers[TAP_SUBS_MSG] = code.parse_code
parsers[CLICK_SUBS_MSG] = code.parse_code

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
function print_text(parsed_data)
    local i = 0
    for line in parsed_data.string:gmatch("([^\n]*)\n?") do
        if line ~= "" then
			if frame.HARDWARE_VERSION == "Frame" then
				frame.display.text(line, 1, i * 60 + 1)
			else
				frame.display.text(line, 1, i * 20 + 1, 0xFFFFFF)
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

-- message handlers, dispatched in arrival order by the main loop
local handlers = {}

handlers[CAPTURE_SETTINGS_MSG] = function(parsed_data)
	-- visual indicator of capture and send
	show_flash()
	local rc, err
	if frame.HARDWARE_VERSION == "Frame" then
		rc, err = pcall(camera.capture_and_send, parsed_data)
	else
		rc, err = pcall(camera.capture_and_send, {resolution = 640, quality = parsed_data.quality})
	end
	clear_display()

	if rc == false then
		print(err)
	end
end

handlers[AUTO_EXP_SETTINGS_MSG] = function(parsed_data)
	if frame.HARDWARE_VERSION == "Frame" then
		rc, err = pcall(camera.set_auto_exp_settings, parsed_data)

		if rc == false then
			print(err)
		end
	end
end

handlers[MANUAL_EXP_SETTINGS_MSG] = function(parsed_data)
	if frame.HARDWARE_VERSION == "Frame" then
		rc, err = pcall(camera.set_manual_exp_settings, parsed_data)

		if rc == false then
			print(err)
		end
	end
end

handlers[TEXT_MSG] = function(parsed_data)
	if parsed_data.string ~= nil then
		print_text(parsed_data)
	end
end

handlers[TAP_SUBS_MSG] = function(parsed_data)
	if parsed_data.value == 1 then
		-- start subscription to tap events
		print('subscribing for taps')
		frame.imu.tap_callback(handle_tap)
	else
		-- cancel subscription to tap events
		print('cancel subscription for taps')
		frame.imu.tap_callback(nil)
	end
end

handlers[CLICK_SUBS_MSG] = function(parsed_data)
	if parsed_data.value == 1 then
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
				-- process any raw data items, returns array of parsed items
				local items = data.process_raw_items()

				for i = 1, #items do
					local flag = items[i][1]
					local raw = items[i][2]

					if parsers[flag] then
						local parsed = parsers[flag](raw)
						if handlers[flag] then
							handlers[flag](parsed)
						end
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
