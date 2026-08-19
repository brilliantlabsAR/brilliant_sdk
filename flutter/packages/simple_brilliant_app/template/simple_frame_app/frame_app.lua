local data = require('data.min')
local battery = require('battery.min')
local code = require('code.min')
local sprite = require('sprite.min')
local plain_text = require('plain_text.min')

-- Phone to Frame flags
-- TODO sample messages only
USER_SPRITE = 0x20
TEXT_MSG = 0x12
CLEAR_MSG = 0x10

-- message parsers, keyed by message flag
local parsers = {}
parsers[USER_SPRITE] = sprite.parse_sprite
parsers[TEXT_MSG] = plain_text.parse_plain_text
parsers[CLEAR_MSG] = code.parse_code

function clear_display()
	if frame.HARDWARE_VERSION == "Frame" then
		frame.display.text(" ", 1, 1)
		frame.display.show()
	else
		-- Halo
		frame.display.clear(0x000000)
	end
end

-- draw the current text on the display
function print_text(parsed_data)
	local i = 0
	for line in parsed_data.string:gmatch("([^\n]*)\n?") do
		if line ~= "" then
			if frame.HARDWARE_VERSION == "Frame" then
				frame.display.text(line, 1, i * 60 + 1)
			else
				-- Halo: default Dogica 8px font, 10px line advance
				frame.display.text(line, 1, i * 20 + 1, parsed_data.color)
			end
			i = i + 1
		end
	end
	if frame.HARDWARE_VERSION == "Frame" then
		frame.display.show()
	end
end

-- message handlers, dispatched in arrival order by the main loop
local handlers = {}

handlers[TEXT_MSG] = function(parsed_data)
	if parsed_data.string ~= nil then
		print_text(parsed_data)
	end
end

handlers[USER_SPRITE] = function(spr)
	-- show the sprite
	frame.display.bitmap(1, 1, spr.width, 2^spr.bpp, 0, spr.pixel_data)
	if frame.HARDWARE_VERSION == "Frame" then
		frame.display.show()
	end
end

handlers[CLEAR_MSG] = function(parsed_data)
	clear_display()
end

-- Main app loop
function app_loop()
	clear_display()
	local last_batt_update = 0
	print("Frame app started")

	while true do
		rc, err = pcall(
			function()
				-- process any raw data items, returns array of {flag, raw} pairs
				local items = data.process_raw_items()

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

				-- periodic battery level updates on Frame
				-- (Halo reports battery via the standard BLE battery service)
				if frame.HARDWARE_VERSION == "Frame" then
					last_batt_update = battery.send_batt_if_elapsed(last_batt_update, 120)
				end

				frame.sleep(0.1)
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
