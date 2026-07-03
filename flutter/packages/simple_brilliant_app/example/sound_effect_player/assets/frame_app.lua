local data = require('data.min')
local battery = require('battery.min')

-- Phone to Frame flags
PLAY_SOUND_MSG = 0x20

-- Parse a TxSoundEffect message: a Uint32 (big-endian) seed
-- followed by the firmware sound preset name (e.g. "jump")
local function parse_sound_effect(raw)
	local msg = {}
	msg.seed = string.unpack('>I4', raw)
	msg.name = string.sub(raw, 5)
	return msg
end

-- message parsers, keyed by message flag
local parsers = {}
parsers[PLAY_SOUND_MSG] = parse_sound_effect

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

	print('Frame App Started')

	-- message handlers, dispatched in arrival order by the main loop
	local handlers = {}

	handlers[PLAY_SOUND_MSG] = function(msg)
		if frame.sound == nil then
			print('Error: this device does not support frame.sound')
			return
		end

		-- play the named firmware sound preset; the seed makes the
		-- randomized sound reproducible
		local ok, err = frame.sound.play(msg.name, {seed=msg.seed})

		if ok then
			print(msg.name .. ' (' .. tostring(msg.seed) .. ')')
		else
			print('Error: ' .. tostring(err))
		end
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
