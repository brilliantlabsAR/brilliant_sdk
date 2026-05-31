local data = require('data.min')
local code = require('code.min')
local audio = require('audio.min')
local camera = require('camera.min')

-- Phone to Frame flags
AUDIO_SUBS_MSG = 0x30
CAPTURE_SETTINGS_MSG = 0x0d

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
	frame.display.text('Frame App Started', 1, 1)
	frame.display.show()
	frame.camera.power_save(false)

	local streaming = false
	local last_auto_exp_time = 0

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

					if flag == AUDIO_SUBS_MSG then
						local msg = code.parse_code(raw)
						if msg.value == 1 then
							audio_data = ''
							streaming = true
							audio.start{sample_rate=8000, bit_depth=16}
							frame.display.text("\u{F0010}", 300, 1)
						else
							-- don't set streaming = false here, it will be set
							-- when all the audio data is flushed
							audio.stop()
							clear_display()
						end
						frame.display.show()

					elseif flag == CAPTURE_SETTINGS_MSG then
						-- visual indicator of capture and send
						show_flash()
						rc, err = pcall(camera.capture_and_send, camera.parse_capture_settings(raw))
						clear_display()

						if rc == false then
							print(err)
						end
					end
				end

				-- send any pending audio data back
				-- Streams until AUDIO_SUBS_MSG is sent from host with a value of 0
				if streaming then
					sent = audio.read_and_send_audio()

					if (sent == nil) then
						streaming = false
					end

					-- 8kHz/8 bit is 8000b/s, which is 33 packets/second, or 1 every 30ms
					frame.sleep(0.005)
				else
					-- not streaming, sleep for longer
					frame.sleep(0.1)
				end

				-- run the autoexposure loop every 100ms
				if frame.HARDWARE_VERSION == 'Frame' and camera.is_auto_exp then
					local t = frame.time.utc()
					if (t - last_auto_exp_time) > 0.1 then
						camera.run_auto_exposure()
						last_auto_exp_time = t
					end
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