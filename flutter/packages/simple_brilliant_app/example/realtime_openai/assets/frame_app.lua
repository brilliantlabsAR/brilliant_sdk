local data = require('data.min')
local battery = require('battery.min')
local code = require('code.min')
local plain_text = require('plain_text.min')

-- Phone to Frame flags
CLEAR_MSG = 0x10
CLICK_SUBS_MSG = 0x11
TEXT_MSG = 0x12
START_LISTENING_MSG = 0x30
STOP_LISTENING_MSG = 0x31
START_PLAYBACK_MSG = 0x40
STOP_PLAYBACK_MSG = 0x41

-- Frame to Phone flags
AUDIO_DATA_NON_FINAL_MSG = 0x05
AUDIO_DATA_FINAL_MSG = 0x06
CLICK_MSG = 0x0B

-- message parsers, keyed by message flag
local parsers = {}
parsers[CLEAR_MSG] = code.parse_code
parsers[CLICK_SUBS_MSG] = code.parse_code
parsers[TEXT_MSG] = plain_text.parse_plain_text
-- START_LISTENING carries three named config bytes (see its handler), not a
-- single code, so it takes the raw payload straight through.
parsers[START_LISTENING_MSG] = function(raw) return raw end
parsers[STOP_LISTENING_MSG] = code.parse_code
parsers[START_PLAYBACK_MSG] = code.parse_code
parsers[STOP_PLAYBACK_MSG] = code.parse_code

local listening = false
local mtu = frame.bluetooth.max_length() - 1 -- leave 1 byte for message type

-- LC3-encoded microphone audio at 32kbps/10ms is produced in 40-byte frames;
-- read whole frames so the phone-side decoder stays frame-aligned
local read_size = mtu - (mtu % 40)
if read_size > 240 then read_size = 240 end

function clear_display()
	frame.display.clear()
end

-- default 9pt font is ~18px tall, so 22px line spacing gives a small gap
LINE_SPACING = 22

function show_text(text)
	frame.display.clear()
	local i = 0
	for line in text:gmatch("([^\n]*)\n?") do
		if line ~= "" then
			frame.display.text(line, 15, 50 + i * LINE_SPACING, 0xFFFFFF)
			i = i + 1
		end
	end
end

function handle_click(type)
	pcall(frame.bluetooth.send, string.char(CLICK_MSG) .. string.char(type))
end

-- message handlers, dispatched in arrival order by the main loop
local handlers = {}

handlers[TEXT_MSG] = function(parsed_data)
	if parsed_data.string ~= nil then
		show_text(parsed_data.string)
	end
end

handlers[CLEAR_MSG] = function(parsed_data)
	clear_display()
end

handlers[CLICK_SUBS_MSG] = function(parsed_data)
	if parsed_data.value == 1 then
		frame.button.single(function() handle_click(1) end)
		frame.button.double(function() handle_click(2) end)
		frame.button.long(function() handle_click(3) end)
	else
		frame.button.single(nil)
		frame.button.double(nil)
		frame.button.long(nil)
	end
end

handlers[START_LISTENING_MSG] = function(raw)
	-- Halo-only: stream LC3-encoded microphone audio at 16kHz mono.
	-- Payload is three named bytes (see main.dart _micStartPayload):
	--   [1] gain code 0..20  -> mic gain -10..10  ([1] - 10)
	--   [2] aec   0/1         -> echo cancellation on/off
	--   [3] voice 0/1         -> voice-band mode on/off (band-pass the AEC
	--                            output, so the server VAD only hears near-end)
	local gain, aec_on, voice = 0, true, false
	if raw ~= nil and #raw >= 3 then
		gain = string.byte(raw, 1) - 10
		aec_on = string.byte(raw, 2) ~= 0
		voice = string.byte(raw, 3) ~= 0
	end
	if gain < -10 then gain = -10 elseif gain > 10 then gain = 10 end
	pcall(frame.microphone.start, {encoder='lc3', sample_rate=16000, bitrate=32000, channels=1, gain=gain})
	pcall(frame.microphone.aec, aec_on)
	pcall(frame.microphone.voice, voice)
	listening = true
end

handlers[STOP_LISTENING_MSG] = function(parsed_data)
	pcall(frame.microphone.stop)
end

handlers[START_PLAYBACK_MSG] = function(parsed_data)
	-- Halo-only: accept LC3-encoded audio on the audio characteristic
	-- value carries the speaker volume (1..100; 0 -> default 100)
	local vol = parsed_data.value
	if vol == nil or vol < 1 or vol > 100 then vol = 100 end
	pcall(frame.speaker.start, {encoder="lc3", sample_rate=16000, channels=1, duration=1000, bitrate=32000, volume=vol})
end

handlers[STOP_PLAYBACK_MSG] = function(parsed_data)
	pcall(frame.speaker.stop)
end

-- Main app loop
function app_loop()
	frame.display.power_save(false)
	frame.display.brightness(25)
	clear_display()
	local last_batt_update = 0
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

		-- send any pending LC3 microphone audio to the phone
		-- Streams until STOP_LISTENING_MSG is sent from phone
		-- (prioritize the reading and sending about 20x compared to checking for other events)
		if listening then
			for i=1,20 do
				local audio_data = frame.microphone.read(read_size)

				-- Calling frame.microphone.stop() will allow this to break the loop
				if audio_data == nil then
					-- send an end-of-stream message back to the phone
					pcall(frame.bluetooth.send, string.char(AUDIO_DATA_FINAL_MSG))
					listening = false
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
		if listening then frame.sleep(0.01) else frame.sleep(0.1) end
	end
end

-- run the main app loop
app_loop()
