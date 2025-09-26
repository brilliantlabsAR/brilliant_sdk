-- Module to parse Sprites sent from phoneside app as TxTextSpriteBlock messages
local _M = {}

-- Parse the text sprite block message raw data. Unpack the header fields.
-- width(Uint16), max_display_rows(Uint8), lines(Uint8), [x_offset (Uint16), y_offset (Uint16)] * lines
function _M.parse_text_sprite_block(data, prev)
	if string.byte(data, 1) == 0xFF then
		-- new block
		local text_sprite_block = {}
		text_sprite_block.width = string.byte(data, 2) << 8 | string.byte(data, 3)
		text_sprite_block.max_display_rows = string.byte(data, 4)
		text_sprite_block.lines = string.byte(data, 5)
		-- for each line, parse the offsets
		local offsets = {}
		for i=0,text_sprite_block.lines-1 do
			local xy = {}
			xy.x = string.byte(data, 5+(4*i)+1) << 8 | string.byte(data, 5+(4*i)+2)
			xy.y = string.byte(data, 5+(4*i)+3) << 8 | string.byte(data, 5+(4*i)+4)
			table.insert(offsets, xy)
		end
		text_sprite_block.offsets = offsets
		text_sprite_block.sprites = {}
		text_sprite_block.last_sprite_index = 0
		text_sprite_block.first_sprite_index = 0
		return text_sprite_block
	else
		-- no existing TextSpriteBlock to accumulate into, drop this sprite
		if prev == nil then
			return nil
		end

		-- increment our counters (and index into sprites table)
		prev.last_sprite_index = prev.last_sprite_index + 1
		if prev.first_sprite_index == 0 then
			prev.first_sprite_index = 1
		end

		-- if we have more than max_display_rows with this new line then
		-- remove the earliest sprite and increment the first_sprite_index
		if (prev.last_sprite_index - prev.first_sprite_index + 1) > prev.max_display_rows then
			prev.sprites[prev.first_sprite_index] = nil
			prev.first_sprite_index = prev.first_sprite_index + 1
		end

		-- new text sprite line
		local sprite = {}
		sprite.width = string.byte(data, 1) << 8 | string.byte(data, 2)
		sprite.height = string.byte(data, 3) << 8 | string.byte(data, 4)
		sprite.compressed = string.byte(data, 5) > 0
		sprite.bpp = string.byte(data, 6)
		sprite.num_colors = string.byte(data, 7)
		sprite.palette_data = string.sub(data, 8, 8 + sprite.num_colors * 3 - 1)
		sprite.pixel_data = string.sub(data, 8 + sprite.num_colors * 3)

		-- add this sprite to the end
		prev.sprites[prev.last_sprite_index] = sprite

		return prev
	end
end

return _M