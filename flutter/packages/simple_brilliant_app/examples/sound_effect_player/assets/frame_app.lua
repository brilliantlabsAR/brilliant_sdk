local data = require('data.min')
local battery = require('battery.min')
local code = require('code.min')
local sfxr = require('sfxr.min')

-- Phone to Frame flags
PLAY_SFXR_MSG = 0x20
CLEAR_MSG = 0x10

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[PLAY_SFXR_MSG] = sfxr.parse_sfxr
data.parsers[CLEAR_MSG] = code.parse_code

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
    local last_batt_update = 0

	if frame.HARDWARE_VERSION ~= 'Frame' then
		frame.display.brightness(50)
		frame.display.power_save(false)
	end

    print('Frame App Started')

	while true do
		rc, err = pcall(
            function()
				-- process any raw data items, if ready
				local items_ready = data.process_raw_items()

				-- one or more full messages received
				if items_ready > 0 then

					if (data.app_data[PLAY_SFXR_MSG] ~= nil) then
						-- retrieve the sfxr data
						local sound = data.app_data[PLAY_SFXR_MSG]
						print('Playing SFXR sound effect')

						local SAMPLE_RATE = 8000
						local BIT_DEPTH = 16
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

					if (data.app_data[CLEAR_MSG] ~= nil) then
						-- clear the display
						clear_display()
						data.app_data[CLEAR_MSG] = nil
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