local data = require('data.min')

-- Phone to Frame flags
local PLAY_SOUND_FLAG = 0x20

-- Parse a TxSoundEffect message: a Uint32 (big-endian) seed
-- followed by the firmware sound preset name (e.g. "jump")
local function parse_sound_effect(raw)
	local msg = {}
	msg.seed = string.unpack('>I4', raw)
	msg.name = string.sub(raw, 5)
	return msg
end

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

					if flag == PLAY_SOUND_FLAG then
						local msg = parse_sound_effect(raw)

						if frame.sound == nil then
							print('Error: this device does not support frame.sound')
						else
							-- play the named firmware sound preset; the seed makes
							-- the randomized sound reproducible
							local ok, play_err = frame.sound.play(msg.name, {seed=msg.seed})

							if ok then
								print(msg.name .. ' (' .. tostring(msg.seed) .. ')')
							else
								print('Error: ' .. tostring(play_err))
							end
						end
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
