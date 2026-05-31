local data = require('data.min')
local code = require('code.min')
local audio = require('audio.min')

-- Phone to Frame flags
AUDIO_SUBS_MSG = 0x30

function clear_display()
	if frame.HARDWARE_VERSION == 'Frame' then
		frame.display.text(' ', 1, 1)
		frame.display.show()
	else
		frame.display.clear()
	end
end

-- Main app loop
function app_loop()
	clear_display()
	frame.display.text('Frame App Started', 50, 50)
	frame.display.show()

	local streaming = false

	-- tell the host program that the frameside app is ready (waiting on await_print)
	print('Frame app is running')

	-- calculate delay per packet based on max bluetooth length and audio bitrate
	local delay_per_packet = frame.bluetooth.max_length() / 12000 -- 8kHz/16bit audio with some margin

	while true do
        rc, err = pcall(
            function()
				-- process any raw data items, if ready
				local items = data.process_raw_items()

				for i = 1, #items do
					local flag = items[i][1]
					local raw = items[i][2]

					if flag == AUDIO_SUBS_MSG then
						local msg = code.parse_code(raw)
						if msg.value == 1 then
							-- 'start' message
							audio_data = ''
							streaming = true
							audio.start{sample_rate=8000, bit_depth=16}
							if frame.HARDWARE_VERSION == 'Frame' then
								frame.display.text("\u{F0010}", 300, 1)
								frame.display.show()
							else
								frame.display.clear()
								frame.display.text("Rec", 50, 50)
							end
						else
							-- 'stop' message
							-- don't set streaming = false here, it will be set
							-- when all the audio data is flushed
							audio.stop()
							if frame.HARDWARE_VERSION == 'Frame' then
								frame.display.text(" ", 1, 1)
								frame.display.show()
							else
								frame.display.clear()
							end
						end
					end
				end

				-- send any pending audio data back
				-- Streams until AUDIO_SUBS_MSG is sent from host with a value of 0
				if streaming then
					-- read_and_send_audio() sends one MTU worth of samples
					-- so we want to call it a bit more frequently than the audio bitrate
					-- to catch up if we fall behind
					local sent = nil
					for i = 1, 10 do
						sent = audio.read_and_send_audio()
						if sent == 0 then
							break
						end
					end
					if sent == nil then
						streaming = false
					end

					-- 16kHz/16 bit is 32000b/s, i.e. 32000/MTU packets per second
					-- but we send up to 10 packets and sleep for (MTU/24k) between packets
					frame.sleep(delay_per_packet)
				else
					-- not streaming, sleep for longer
					frame.sleep(0.1)
				end
			end
		)
		-- Catch an error (including the break signal) here
		if rc == false then
			-- send the error back on the stdout stream and clear the display
			print(err)
			clear_display()
			break
		end
	end
end

-- run the main app loop
app_loop()
