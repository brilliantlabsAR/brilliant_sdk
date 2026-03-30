local data = require('data.min')
local battery = require('battery.min')
local code = require('code.min')
local sfxr = require('sfxr.min')

-- Phone to Frame flags
PLAY_SFXR_MSG = 0x20
PLAY_RANDOM_MSG = 0x21

-- message parsers, keyed by message flag
local parsers = {}
parsers[PLAY_SFXR_MSG] = sfxr.parse_sfxr
parsers[PLAY_RANDOM_MSG] = code.parse_code

local SAMPLE_RATE = 16000
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
	local random_choice = math.random(1, 6)
	if random_choice == 1 then
			sound:randomPickup()
			print("Pickup!")
	elseif random_choice == 2 then
			sound:randomLaser()
			print("Laser!")
	elseif random_choice == 3 then
			sound:randomPowerup()
			print("Powerup!")
	elseif random_choice == 4 then
			sound:randomHit()
			print("Hit!")
	elseif random_choice == 5 then
			sound:randomJump()
			print("Jump!")
	elseif random_choice == 6 then
			sound:randomBlip()
			print("Blip!")
	-- elseif random_choice == 7 then
	-- 		sound:randomExplosion()
	-- 		print("Explosion!")
	-- Explosions have lots of low frequencies that can blow out the speaker, so we'll skip them for now
	else
			sound:randomPickup()
	end
end

-- Main app loop
function app_loop()
	clear_display()
    local last_batt_update = 0

	if frame.HARDWARE_VERSION ~= 'Frame' then
		frame.display.brightness(50)
		frame.display.power_save(false)
	end

    print('Frame App Started')

	-- message handlers, dispatched in arrival order by the main loop
	local handlers = {}

	handlers[PLAY_SFXR_MSG] = function(sound)
		-- retrieve the sfxr data
		print('Playing SFXR sound effect')

		sound.supersampling = 8
		frame.speaker.start{encoder='pcm', sample_rate=SAMPLE_RATE, bit_depth=BIT_DEPTH, channels=1}

		local pack = string.pack
		local t = {}
		local i = 1
		for v in sound:generate(SAMPLE_RATE, BIT_DEPTH) do
				t[i] = pack("<i2", math.floor(v))
				i = i + 1
				-- due to memory constraints, let's bail after 10kB
				if i > 5000 then
						break
				end
		end
		print("Sound generated")
		frame.speaker.play(table.concat(t))
		print("Sound played")
		local num_samples = #t
		for n=1, num_samples do t[n]=nil end
	end

	handlers[PLAY_RANDOM_MSG] = function(item)
		print("Playing random sfxr sound effect")
		local sound = sfxr.newSound()
		sound.waveform = sfxr.WAVEFORM.SQUARE

		print("Randomizing sound")
		randomize_sound(sound)
		sound.supersampling = 8

		frame.speaker.start{encoder='pcm', sample_rate=SAMPLE_RATE, bit_depth=BIT_DEPTH, channels=1}

		print("Generating and playing sound")
		local pack = string.pack
		local t = {}
		local i = 1
		for v in sound:generate(SAMPLE_RATE, BIT_DEPTH) do
			t[i] = pack("<i2", math.floor(v))
			i = i + 1
			-- due to memory constraints, let's bail after 10kB
			if i > 5000 then
					break
			end
		end
		print("Sound generated")
		frame.speaker.play(table.concat(t))
		print("Sound played")
		local num_samples = #t
		for n=1, num_samples do t[n]=nil end
	end

	while true do
		rc, err = pcall(
            function()
				-- drain the message queue, parse and dispatch in arrival order
                local items = data.process_raw_items()

				for i = 1, #items do
					local flag = items[i][1]
					local raw  = items[i][2]

					if parsers[flag] == nil then
						print('Error: No parser for flag: ' .. tostring(flag))
					else
						local parsed = parsers[flag](raw)

						if handlers[flag] ~= nil then
							handlers[flag](parsed)
						else
							print('Error: No handler for flag: ' .. tostring(flag))
						end
					end
				end

				-- periodic battery level updates
				last_batt_update = battery.send_batt_if_elapsed(last_batt_update, 120)
				-- can't sleep for long, might be lots of incoming bluetooth data to process
				frame.sleep(0.01)
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