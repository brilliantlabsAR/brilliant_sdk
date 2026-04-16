local data = require('data.min')
local code = require('code.min')
local sfxr = require('sfxr')

-- Phone to Frame flags
local USER_CODE_FLAG = 0x42
local SFXR_FLAG = 0x43

local SAMPLE_RATE = 8000
local BIT_DEPTH = 16

function clear_display()
	if frame.HARDWARE_VERSION == 'Frame' then
		frame.display.text(' ', 1, 1)
		frame.display.show()
	else
		frame.display.clear()
	end
end

function randomize_sound(sound)
	local random_choice = math.random(1, 7)
	if random_choice == 1 then
		sound:randomPickup()
		print("Pickup!")
	elseif random_choice == 2 then
		sound:randomLaser()
		print("Laser!")
	elseif random_choice == 3 then
		sound:randomExplosion()
		print("Explosion!")
	elseif random_choice == 4 then
		sound:randomPowerup()
		print("Powerup!")
	elseif random_choice == 5 then
		sound:randomHit()
		print("Hit!")
	elseif random_choice == 6 then
		sound:randomJump()
		print("Jump!")
	elseif random_choice == 7 then
		sound:randomBlip()
		print("Blip!")
	else
		sound:randomExplosion()
	end
end

-- Main app loop
function app_loop()
	clear_display()
	frame.display.text('App Started', 1, 1)
	frame.display.show() -- no-op on Halo

	-- tell the host program that the frameside app is ready (waiting on await_print)
	print('App Started')

	while true do
        rc, err = pcall(
            function()
				-- process any raw data items, if ready
				local items = data.process_raw_items()

				for i = 1, #items do
					local flag = items[i][1]
					local raw = items[i][2]

					if flag == USER_CODE_FLAG then
						local msg = code.parse_code(raw)
						if frame.HARDWARE_VERSION ~= 'Frame' then
							if msg.value == 1 then
								print("Starting speaker")
								frame.speaker.start{encoder='pcm', sample_rate=SAMPLE_RATE, bit_depth=BIT_DEPTH, channels=1}

							elseif msg.value == 0 then
								print("Stopping speaker")
								frame.speaker.stop()

							elseif msg.value == 2 then
								print("Playing sine wave tone")
								local pitch = 880 -- A5
								local samples = {}
								local pack = string.pack
								local step_size = (2 * math.pi * pitch) / SAMPLE_RATE -- 880 Hz tone at 8 kHz sample rate
								local period = math.floor(SAMPLE_RATE / pitch) -- samples in one period

								for j = 1, period do
									local raw_num = math.sin(j * step_size) * 8192 -- scale to quarter volume signed 16-bit range
									local int_val = math.floor(raw_num)
									samples[j] = pack("<i2", int_val)
								end
								local one_period = table.concat(samples)

								local repeat_count = math.ceil(SAMPLE_RATE / period) -- play enough periods for 1 second
								for j = 1, repeat_count do
									frame.speaker.play(one_period)
									frame.sleep(period/SAMPLE_RATE) -- yield to allow speaker buffer to drain
								end

								-- Clear samples table and force garbage collection
								local num_samples = #samples
								for n=1, num_samples do samples[n]=nil end

							elseif msg.value == 3 then
								print("Playing random sfxr sound effect")

								print("New sound")
								local sound = sfxr.newSound()
								sound.waveform = sfxr.WAVEFORM.SQUARE

								print("Randomizing sound")
								randomize_sound(sound)
								sound.supersampling = 4

								print("Generating and playing sound")
								local pack = string.pack
								local t = {}
								local k = 1
								for v in sound:generate(SAMPLE_RATE, BIT_DEPTH) do
									t[k] = pack("<i2", math.floor(v))
									k = k + 1
									-- due to memory constraints, let's bail after 10kB
									if k > 5000 then
										break
									end
								end
								print("Sound generated")
								frame.speaker.play(table.concat(t))
								print("Sound played")
								local num_samples = #t
								for n=1, num_samples do t[n]=nil end
							end

							collectgarbage('collect')
						else
							frame.display.text('Speaker not available on Frame', 1, 1)
							frame.display.show()
						end
						collectgarbage('collect')

					elseif flag == SFXR_FLAG then
						local sfxr_sound = sfxr.parse_sfxr(raw)
						if frame.HARDWARE_VERSION ~= 'Frame' then
							print("Generating and playing received sfxr sound effect")
							sfxr_sound.supersampling = 8
							sfxr_sound:generate_and_play(SAMPLE_RATE, BIT_DEPTH, 5000)
							print("Sound played")
						else
							frame.display.text('Speaker not available on Frame', 1, 1)
							frame.display.show()
						end
						collectgarbage('collect')
					end
				end

				-- sleep and wake up often enough for control messages
				frame.sleep(0.1)
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