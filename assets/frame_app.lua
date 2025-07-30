local data = require('data.min')
local battery = require('battery.min')
local code = require('code.min')
local plain_text = require('plain_text.min')

-- Phone to Frame flags
TEXT_MSG = 0x12
CLEAR_MSG = 0x10
START_AUDIO_MSG = 0x30
STOP_AUDIO_MSG = 0x31

-- Frame to Phone flags
AUDIO_DATA_NON_FINAL_MSG = 0x05
AUDIO_DATA_FINAL_MSG = 0x06

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[TEXT_MSG] = plain_text.parse_plain_text
data.parsers[CLEAR_MSG] = code.parse_code
data.parsers[START_AUDIO_MSG] = code.parse_code
data.parsers[STOP_AUDIO_MSG] = code.parse_code

function show_text(text)
	if frame.HARDWARE_VERSION == "Frame" then
		frame.display.text(text, 1, 1)
		frame.display.show()
	else
		-- Halo
		frame.display.text(text, 50, 50, 0xFFFFFF)
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


-- Main app loop
function app_loop()
	clear_display()
    local last_batt_update = 0
	local streaming = false
	local audio_data = ''
	local mtu = frame.bluetooth.max_length()
	-- data buffer needs to be even for reading from microphone
	if mtu % 2 == 1 then mtu = mtu - 1 end
	print("Frame app started")

	while true do
		-- process any raw data items, if ready
		local items_ready = data.process_raw_items()

		-- one or more full messages received
		if items_ready > 0 then

			if (data.app_data[TEXT_MSG] ~= nil and data.app_data[TEXT_MSG].string ~= nil) then
				local i = 0
				for line in data.app_data[TEXT_MSG].string:gmatch("([^\n]*)\n?") do
					if line ~= "" then
						if frame.HARDWARE_VERSION == "Frame" then
							frame.display.text(line, 1, i * 60 + 1)
						else
							frame.display.text(line, 50, 50 + i * 60, 0xFFFFFF)
						end
						i = i + 1
					end
				end
				frame.display.show()
			end

			if (data.app_data[CLEAR_MSG] ~= nil) then
				clear_display()
				data.app_data[CLEAR_MSG] = nil
			end

			if (data.app_data[START_AUDIO_MSG] ~= nil) then
				audio_data = ''
				if frame.HARDWARE_VERSION == "Frame" then
					pcall(frame.microphone.start, {sample_rate=8000, bit_depth=8})
				else
					-- Halo
					pcall(frame.microphone.start, {sample_rate=16000, bit_depth=16, channels=1})
				end
				streaming = true
				show_text("Streaming Audio")

				data.app_data[START_AUDIO_MSG] = nil
			end

			if (data.app_data[STOP_AUDIO_MSG] ~= nil) then
				pcall(frame.microphone.stop)
				clear_display()

				data.app_data[STOP_AUDIO_MSG] = nil
			end

		end

		-- send any pending audio data back
		-- Streams until STOP_AUDIO_MSG is sent from phone
		-- (prioritize the reading and sending about 20x compared to checking for other events e.g. STOP_AUDIO_MSG)
		for i=1,20 do
			if streaming then
				audio_data = frame.microphone.read(mtu)

				-- Calling frame.microphone.stop() will allow this to break the loop
				if audio_data == nil then
					-- send an end-of-stream message back to the phone
					pcall(frame.bluetooth.send, string.char(AUDIO_DATA_FINAL_MSG))
					frame.sleep(0.0025)
					streaming = false
					break

				-- send the data that was read
				elseif audio_data ~= '' then
					pcall(frame.bluetooth.send, string.char(AUDIO_DATA_NON_FINAL_MSG) .. audio_data)
					frame.sleep(0.0025)
				end
			end
		end

        -- periodic battery level updates, 120s for a camera app
		-- TODO check timekeeping functions, this is returning true every iteration (0.1s)
        --last_batt_update = battery.send_batt_if_elapsed(last_batt_update, 120)

		if not streaming then frame.sleep(0.1) end
	end
end

-- run the main app loop
app_loop()