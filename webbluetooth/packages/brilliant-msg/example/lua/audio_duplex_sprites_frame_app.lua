local data = require('data.min')
local image_sprite_block = require('image_sprite_block.min')

-- Phone to Frame flags
IMAGE_SPRITE_BLOCK = 0x20
AUDIO_START_MSG = 0x40
AUDIO_STOP_MSG = 0x41

-- Frame to Phone flags (RxAudio defaults)
AUDIO_DATA_NON_FINAL_MSG = 0x05
AUDIO_DATA_FINAL_MSG = 0x06

-- where the 128x128 image goes on Halo's 256x256 round display
IMAGE_X = 65
IMAGE_Y = 65

function clear_display()
	if frame.HARDWARE_VERSION == 'Frame' then
		frame.display.text(' ', 1, 1)
		frame.display.show()
	else
		frame.display.clear()
	end
end

-- sends a whole notification, retrying while the Bluetooth is busy
function send(payload)
	while true do
		if pcall(frame.bluetooth.send, payload) then
			return
		end
		frame.sleep(0.0025)
	end
end

-- Main app loop
function app_loop()
	frame.display.power_save(false)
	clear_display()

	-- accumulator for the image sprite block (persists across loop iterations)
	local isb = nil

	-- microphone LC3 stream state
	local mic_on = false
	local mic_chunk = 0
	local mic_bytes = 0

	-- speaker/microphone stats are printed every STATS_PERIOD seconds
	local STATS_PERIOD = 2
	local stats_due = nil
	local images_drawn = 0

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

					if flag == IMAGE_SPRITE_BLOCK then
						-- an updatable block: after the header, strips keep arriving and wrap
						-- around to the top, so each strip is drawn as it arrives
						isb = image_sprite_block.parse_image_sprite_block(raw, isb)
						if isb ~= nil and isb.current_sprite_index > 0 then
							local spr = isb.sprites[isb.current_sprite_index]
							local y_offset = isb.sprite_line_height * (isb.current_sprite_index - 1)
							frame.display.bitmap(IMAGE_X, IMAGE_Y + y_offset, spr.width, 2^spr.bpp, 0, spr.pixel_data, {palette_data=spr.palette_data})
							if isb.current_sprite_index == isb.total_sprites then
								images_drawn = images_drawn + 1
							end
						end

					elseif flag == AUDIO_START_MSG then
						-- spk_rate_khz(1), spk_kbps(1), spk_volume(1), mic_rate_khz(1), mic_kbps(1), interval_ms(1)
						local spk_rate = string.byte(raw, 1) * 1000
						local spk_bitrate = string.byte(raw, 2) * 1000
						local volume = string.byte(raw, 3)
						local mic_rate = string.byte(raw, 4) * 1000
						local mic_bitrate = string.byte(raw, 5) * 1000
						local interval = string.byte(raw, 6)

						-- ask for a shorter connection interval while streaming (0: leave it as it is)
						if interval > 0 then
							frame.bluetooth.connection_interval(interval)
						end

						-- LC3 duration is in units of 10 microseconds: 1000 = 10 ms frames
						frame.speaker.start{encoder='lc3', sample_rate=spk_rate, duration=1000, channels=1, bitrate=spk_bitrate, volume=volume}

						if mic_bitrate > 0 then
							frame.microphone.start{encoder='lc3', sample_rate=mic_rate, bit_depth=16, duration=1000, bitrate=mic_bitrate}
							-- read whole LC3 frames, as many as fit in one link-layer packet's
							-- notification (244 bytes) after the data marker and flag bytes
							local lc3_frame = mic_bitrate // 800
							local max_payload = math.min(frame.bluetooth.max_length() - 1, 242)
							mic_chunk = math.max(1, max_payload // lc3_frame) * lc3_frame
							-- microphone.read() takes an even number of bytes
							if mic_chunk % 2 == 1 then mic_chunk = mic_chunk - lc3_frame end
							mic_on = true
						end

						frame.speaker.stats(true)
						mic_bytes = 0
						images_drawn = 0
						stats_due = frame.time.utc() + STATS_PERIOD

					elseif flag == AUDIO_STOP_MSG then
						frame.speaker.stop()
						if mic_on then
							frame.microphone.stop()
						end
					end
				end

				-- send the microphone's LC3 frames back as they are encoded
				if mic_on then
					for _ = 1, 10 do
						local lc3 = frame.microphone.read(mic_chunk)
						if lc3 == nil then
							-- stopped: flush the end-of-stream marker
							send(string.char(AUDIO_DATA_FINAL_MSG))
							mic_on = false
							break
						elseif lc3 == '' then
							break
						end
						send(string.char(AUDIO_DATA_NON_FINAL_MSG) .. lc3)
						mic_bytes = mic_bytes + #lc3
					end
				end

				-- periodic stats for the stats window just finished
				if stats_due ~= nil and frame.time.utc() >= stats_due then
					local s = frame.speaker.stats(true)
					print(string.format('stats spk_writes=%d spk_bytes=%d rejected=%d ring=%d peak=%d interval=%g decoded=%d plc=%d silence=%d mic_bytes=%d images=%d',
						s.ble_writes, s.ble_bytes, s.ble_rejected, s.ring_bytes, s.ring_peak, frame.bluetooth.connection_interval() or 0,
						s.frames_decoded, s.frames_plc, s.silence_blocks or -1, mic_bytes, images_drawn))
					mic_bytes = 0
					images_drawn = 0
					stats_due = stats_due + STATS_PERIOD
					if not s.streaming then stats_due = nil end
				end

				frame.sleep(0.005)
			end
		)
		-- Catch an error (including the break signal) here
		if rc == false then
			-- send the error back on the stdout stream and clear the display
			print(err)
			pcall(frame.speaker.stop)
			pcall(frame.microphone.stop)
			clear_display()
			break
		end
	end
end

-- run the main app loop
app_loop()
