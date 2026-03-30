local data = require('data.min')
local battery = require('battery.min')
local code = require('code.min')
local plain_text = require('plain_text.min')

-- Phone to Frame flags
TEXT_MSG = 0x12
CLEAR_MSG = 0x10
START_RECORDING_MSG = 0x30
STOP_RECORDING_MSG = 0x31
START_PLAYBACK_MSG = 0x40
STOP_PLAYBACK_MSG = 0x41

-- Frame to Phone flags
AUDIO_DATA_NON_FINAL_MSG = 0x05
AUDIO_DATA_FINAL_MSG = 0x06

-- message parsers, keyed by message flag
local parsers = {}
parsers[TEXT_MSG] = plain_text.parse_plain_text
parsers[CLEAR_MSG] = code.parse_code
parsers[START_RECORDING_MSG] = code.parse_code
parsers[STOP_RECORDING_MSG] = code.parse_code
parsers[START_PLAYBACK_MSG] = code.parse_code
parsers[STOP_PLAYBACK_MSG] = code.parse_code

function show_text(text)
	if frame.HARDWARE_VERSION == "Frame" then
		frame.display.text(text, 1, 1)
		frame.display.show()
	else
		-- Halo
		frame.display.clear()
		frame.display.text(text, 50, 50, 0xFFFFFF)
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

-- message handlers, dispatched in arrival order by the main loop
local handlers = {}

handlers[TEXT_MSG] = function(parsed_data)
	if parsed_data.string ~= nil then
		local i = 0
		if frame.HARDWARE_VERSION ~= "Frame" then
			frame.display.clear()
		end
		for line in parsed_data.string:gmatch("([^\n]*)\n?") do
			if line ~= "" then
				if frame.HARDWARE_VERSION == "Frame" then
					frame.display.text(line, 1, i * 60 + 1)
				else
					frame.display.text(line, 50, 50 + i * 60)
				end
				i = i + 1
			end
		end
		frame.display.show()
	end
end

handlers[CLEAR_MSG] = function(parsed_data)
	clear_display()
end

handlers[START_RECORDING_MSG] = function(parsed_data)
	audio_data = ''
	if frame.HARDWARE_VERSION == "Frame" then
		pcall(frame.microphone.start, {sample_rate=8000, bit_depth=16})
	else
		-- Halo
		pcall(frame.microphone.start, {sample_rate=8000, bit_depth=16, gain=0})
	end
	recording = true
	show_text("Recording Audio")
end

handlers[STOP_RECORDING_MSG] = function(parsed_data)
	pcall(frame.microphone.stop)
	clear_display()
end

handlers[START_PLAYBACK_MSG] = function(parsed_data)
	if frame.HARDWARE_VERSION ~= "Frame" then
		playing = true
		pcall(frame.speaker.start, {encoder="lc3", sample_rate=8000, channels=1, duration=1000, bitrate=32000, volume=100})
	end
	show_text("Playing Audio")
end

handlers[STOP_PLAYBACK_MSG] = function(parsed_data)
	if frame.HARDWARE_VERSION ~= "Frame" then
		playing = false
		pcall(frame.speaker.stop)
		clear_display()
	end
	show_text("Playback Stopped")
end

-- Main app loop
function app_loop()
	frame.display.power_save(false)
	clear_display()
    local last_batt_update = 0
	local recording = false
	local playing = false
	local audio_data = ''
	local mtu = frame.bluetooth.max_length() - 1 -- leave 1 byte for message type
	-- data buffer needs to be even for reading from microphone
	if mtu % 2 == 1 then mtu = mtu - 1 end
	print("Frame app started")

	while true do
		-- process any raw data items, returns array of parsed items
		local items = data.process_raw_items()

		-- one or more full messages received
		if #items > 0 then
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
		end

		-- send any pending audio data back
		-- Streams until STOP_RECORDING_MSG is sent from phone
		-- (prioritize the reading and sending about 20x compared to checking for other events e.g. STOP_RECORDING_MSG)
		if recording then
			for i=1,20 do
				audio_data = frame.microphone.read(mtu)

				-- Calling frame.microphone.stop() will allow this to break the loop
				if audio_data == nil then
					-- send an end-of-stream message back to the phone
					pcall(frame.bluetooth.send, string.char(AUDIO_DATA_FINAL_MSG))
					recording = false
					break

				-- send the data that was read
				elseif audio_data ~= '' then
					pcall(frame.bluetooth.send, string.char(AUDIO_DATA_NON_FINAL_MSG) .. audio_data)

				-- no more data for now
				else
					break
				end
			end
		end

        -- periodic battery level updates, 120s
        last_batt_update = battery.send_batt_if_elapsed(last_batt_update, 120)

		-- sleep a bit less while reading audio from the mic, otherwise just catch the control messages
		if recording then frame.sleep(0.025) else frame.sleep(0.1) end
	end
end

-- run the main app loop
app_loop()
