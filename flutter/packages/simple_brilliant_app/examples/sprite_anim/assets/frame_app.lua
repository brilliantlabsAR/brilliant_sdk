local data = require('data.min')
local battery = require('battery.min')
local code = require('code.min')
local sprite = require('sprite.min')

-- Phone to Frame flags
SPRITE_1 = 0x21
SPRITE_2 = 0x22
SPRITE_3 = 0x23
SPRITE_TEXT_1 = 0x31
SPRITE_TEXT_2 = 0x32
SPRITE_TEXT_3 = 0x33
CLEAR_MSG = 0x10
NEXT_MSG = 0x11

-- message parsers, keyed by message flag
local parsers = {}
parsers[SPRITE_1] = sprite.parse_sprite
parsers[SPRITE_2] = sprite.parse_sprite
parsers[SPRITE_3] = sprite.parse_sprite
parsers[SPRITE_TEXT_1] = sprite.parse_sprite
parsers[SPRITE_TEXT_2] = sprite.parse_sprite
parsers[SPRITE_TEXT_3] = sprite.parse_sprite
parsers[CLEAR_MSG] = code.parse_code
parsers[NEXT_MSG] = code.parse_code

function clear_display()
    if frame.HARDWARE_VERSION == 'Frame' then
		frame.display.text(' ', 1, 1)
		frame.display.show()
	else
		frame.display.clear(0x18309C)
	end
end

-- Main app loop
function app_loop()
	clear_display()
    local last_batt_update = 0
	local all_sprites = {}
	local sprite_state = {}

	if frame.HARDWARE_VERSION ~= 'Frame' then
		frame.display.brightness(50)
		-- special background color for this animation
		frame.display.clear(0x18309C)
	end

    print('Frame App Started')

	-- message handlers, dispatched in arrival order by the main loop
	-- (defined inside app_loop to access all_sprites and sprite_state)
	local handlers = {}

	handlers[SPRITE_1] = function(parsed_data)
		sprite_state[SPRITE_1] = parsed_data
		check_all_sprites_received()
	end

	handlers[SPRITE_2] = function(parsed_data)
		sprite_state[SPRITE_2] = parsed_data
		check_all_sprites_received()
	end

	handlers[SPRITE_3] = function(parsed_data)
		sprite_state[SPRITE_3] = parsed_data
		check_all_sprites_received()
	end

	handlers[SPRITE_TEXT_1] = function(parsed_data)
		sprite_state[SPRITE_TEXT_1] = parsed_data
		check_all_sprites_received()
	end

	handlers[SPRITE_TEXT_2] = function(parsed_data)
		sprite_state[SPRITE_TEXT_2] = parsed_data
		check_all_sprites_received()
	end

	handlers[SPRITE_TEXT_3] = function(parsed_data)
		sprite_state[SPRITE_TEXT_3] = parsed_data
		check_all_sprites_received()
	end

	handlers[CLEAR_MSG] = function(parsed_data)
		-- clear the display
		print('Clear display message received')
		clear_display()
	end

	handlers[NEXT_MSG] = function(parsed_data)
		print('Next sprite message received')
		-- display the next sprite in the sequence
		if #all_sprites > 0 then
			print('Displaying next sprite')
			local spr = table.remove(all_sprites, 1)
			table.insert(all_sprites, spr)
			local spr_text = table.remove(all_sprites, 1)
			table.insert(all_sprites, spr_text)

			-- draw the sprite
			frame.display.clear(0x18309C)
			-- 120x60 @ 101,71
			frame.display.bitmap(101, 71, spr.width, 2^spr.bpp, 0, spr.pixel_data, {palette_data=spr.palette_data})
			-- 140x30 @ 91,136
			frame.display.bitmap(91, 136, spr_text.width, 2^spr_text.bpp, 0, spr_text.pixel_data, {palette_data=spr_text.palette_data})
		end
	end

	function check_all_sprites_received()
		-- do we have all the sprites?
		if (sprite_state[SPRITE_1] ~= nil and
			sprite_state[SPRITE_TEXT_1] ~= nil and
			sprite_state[SPRITE_2] ~= nil and
			sprite_state[SPRITE_TEXT_2] ~= nil and
			sprite_state[SPRITE_3] ~= nil and
			sprite_state[SPRITE_TEXT_3] ~= nil
		) then
			print('All sprites received')
			all_sprites = {
				sprite_state[SPRITE_1],
				sprite_state[SPRITE_TEXT_1],
				sprite_state[SPRITE_2],
				sprite_state[SPRITE_TEXT_2],
				sprite_state[SPRITE_3],
				sprite_state[SPRITE_TEXT_3]
			}
			sprite_state[SPRITE_1] = nil
			sprite_state[SPRITE_2] = nil
			sprite_state[SPRITE_3] = nil
			sprite_state[SPRITE_TEXT_1] = nil
			sprite_state[SPRITE_TEXT_2] = nil
			sprite_state[SPRITE_TEXT_3] = nil
		end
	end

	while true do
		rc, err = pcall(
            function()
				-- process any raw data items, returns array of parsed items
				local items = data.process_raw_items()

				-- one or more full messages received
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

				-- can't sleep for long, might be lots of incoming bluetooth data to process
				frame.sleep(0.001)
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
