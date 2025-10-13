local data = require('data.min')
local battery = require('battery.min')
local code = require('code.min')
local plain_text = require('plain_text.min')

-- Phone to Frame flags
TEXT_MSG = 0x12
CLEAR_MSG = 0x10
START_DATA_SEND_MSG = 0x30

-- Frame to Phone flags
AUDIO_DATA_NON_FINAL_MSG = 0x05
AUDIO_DATA_FINAL_MSG = 0x06

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[TEXT_MSG] = plain_text.parse_plain_text
data.parsers[CLEAR_MSG] = code.parse_code
data.parsers[START_DATA_SEND_MSG] = code.parse_code

function print_text(text)
    local i = 0
    for line in text:gmatch("([^\n]*)\n?") do
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
		frame.display.clear()
	end
end


-- Main app loop
function app_loop()
	clear_display()
    local last_batt_update = 0
	local streaming = false
	local payload = ''
	local mtu = frame.bluetooth.max_length()
	local NUM_PACKETS = 4000

	print("Frame app started")

	while true do
		-- process any raw data items, if ready
		local items_ready = data.process_raw_items()

		-- one or more full messages received
		if items_ready > 0 then

			if (data.app_data[TEXT_MSG] ~= nil and data.app_data[TEXT_MSG].string ~= nil) then
				print_text(data.app_data[TEXT_MSG].string)
				data.app_data[TEXT_MSG] = nil
			end

			if (data.app_data[CLEAR_MSG] ~= nil) then
				clear_display()
				data.app_data[CLEAR_MSG] = nil
			end

			if (data.app_data[START_DATA_SEND_MSG] ~= nil) then
				print_text("Streaming starting")
				streaming = true
				-- send back some data on code 0x30
				payload = "\x30" .. string.rep("A", mtu - 1)
				
				for i=1,NUM_PACKETS do
					pcall(frame.bluetooth.send, payload)
				end

				streaming = false
				data.app_data[START_DATA_SEND_MSG] = nil
			end

		end

        -- periodic battery level updates
		-- TODO re-enable when Halo timekeeping is fixed
        --last_batt_update = battery.send_batt_if_elapsed(last_batt_update, 120)

		if not streaming then frame.sleep(0.1) end
	end
end

-- run the main app loop
app_loop()