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

-- Frame to Phone flags
TAP_MSG = 0x09

-- message parsers, keyed by message flag
local parsers = {}
parsers[CAPTURE_SETTINGS_MSG] = camera.parse_capture_settings
parsers[AUTO_EXP_SETTINGS_MSG] = camera.parse_auto_exp_settings
parsers[MANUAL_EXP_SETTINGS_MSG] = camera.parse_manual_exp_settings
parsers[TEXT_MSG] = plain_text.parse_plain_text
parsers[TAP_SUBS_MSG] = code.parse_code

-- Halo (0.8.8+) passes the gesture kind ('single'/'double'/'triple') and
-- fires once per gesture; Frame passes nothing, once per tap.
local TAP_KIND_CODES = { single = 1, double = 2, triple = 3 }

function handle_tap(kind)
	local payload = string.char(TAP_MSG)
	local kind_code = kind and TAP_KIND_CODES[kind]

	if kind_code then
		payload = payload .. string.char(kind_code)
	end

	rc, err = pcall(frame.bluetooth.send, payload)

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
				-- Halo: default Dogica 8px font, 10px line advance
				frame.display.text(line, 1, i * 20 + 1, parsed_data.color)
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
	frame.sleep(0.04)
end

function show_flash()
	if frame.HARDWARE_VERSION == "Frame" then
		frame.display.bitmap(241, 191, 160, 2, 0, string.rep("\xFF", 400))
		frame.display.bitmap(311, 121, 20, 2, 0, string.rep("\xFF", 400))
		frame.display.show()
	else
		-- Halo: flash the full frame white
		frame.display.clear(0xFFFFFF)
	end
	frame.sleep(0.04)
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
				-- process any raw data items, returns array of {flag, raw} pairs
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
				-- (Halo reports battery via the standard BLE battery service)
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
