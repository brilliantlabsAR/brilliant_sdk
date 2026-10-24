-- Module to parse text pages sent from the hostside app as TxTextPage messages.
-- Unlike text_sprite_block, this keeps the per-line x/y offsets from the header,
-- so circular (chord-fitted) layouts render at their intended positions.
local _M = {}

-- Parse a text page message.
-- Header:  0xFF, width(Uint16), height(Uint16), num_lines(Uint8),
--          then num_lines * [x_offset(Uint16), y_offset(Uint16)]
-- Sprites: one TxSprite per line, sent as subsequent messages on the same
--          msg code: width(Uint16), height(Uint16), compressed(Uint8),
--          bpp(Uint8), num_colors(Uint8), palette, pixel_data
function _M.parse_text_page(data, prev)
	if string.byte(data, 1) == 0xFF then
		-- new page
		local page = {}
		page.width = string.byte(data, 2) << 8 | string.byte(data, 3)
		page.height = string.byte(data, 4) << 8 | string.byte(data, 5)
		page.num_lines = string.byte(data, 6)
		page.offsets = {}
		for i = 0, page.num_lines - 1 do
			local base = 7 + i * 4
			page.offsets[i + 1] = {
				x = string.byte(data, base) << 8 | string.byte(data, base + 1),
				y = string.byte(data, base + 2) << 8 | string.byte(data, base + 3),
			}
		end
		page.sprites = {}
		return page
	else
		-- no existing page to accumulate into, drop this sprite
		if prev == nil then
			return nil
		end

		-- ignore any sprites beyond the declared line count
		if #prev.sprites >= prev.num_lines then
			return prev
		end

		local sprite = {}
		sprite.width = string.byte(data, 1) << 8 | string.byte(data, 2)
		sprite.height = string.byte(data, 3) << 8 | string.byte(data, 4)
		sprite.compressed = string.byte(data, 5) > 0
		sprite.bpp = string.byte(data, 6)
		sprite.num_colors = string.byte(data, 7)
		sprite.palette_data = string.sub(data, 8, 8 + sprite.num_colors * 3 - 1)
		sprite.pixel_data = string.sub(data, 8 + sprite.num_colors * 3)

		table.insert(prev.sprites, sprite)

		return prev
	end
end

-- true once every declared line's sprite has arrived
function _M.is_complete(page)
	return page ~= nil and #page.sprites == page.num_lines
end

-- Draw all received lines at their (x, y) offsets.
-- Display coordinates are 1-based, offsets are 0-based.
-- Halo draws immediately; Frame buffers until frame.display.show().
function _M.draw(page)
	for i, spr in ipairs(page.sprites) do
		local off = page.offsets[i]
		if off then
			frame.display.bitmap(off.x + 1, off.y + 1, spr.width, 2 ^ spr.bpp, 0, spr.pixel_data)
		end
	end
	if frame.HARDWARE_VERSION == 'Frame' then
		frame.display.show()
	end
end

return _M
