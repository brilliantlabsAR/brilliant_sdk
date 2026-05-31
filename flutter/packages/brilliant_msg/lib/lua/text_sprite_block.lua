-- Module to parse Sprites sent from phoneside app as TxTextSpriteBlock messages
local _M = {}

-- Parse the text sprite block message raw data. Unpack the header fields.
-- width(Uint16), max_display_lines(Uint8), lines(Uint8), [x_offset (Uint16), y_offset (Uint16)] * lines
function _M.parse_text_sprite_block(data, prev)
	if string.byte(data, 1) == 0xFF then
		-- new block
		local text_sprite_block = {}
		text_sprite_block.width = string.byte(data, 2) << 8 | string.byte(data, 3)
		text_sprite_block.line_height = string.byte(data, 4) << 8 | string.byte(data, 5)
		text_sprite_block.max_display_lines = string.byte(data, 6)
		text_sprite_block.sprites = {}
		return text_sprite_block
	else
		-- no existing TextSpriteBlock to accumulate into, drop this sprite
		if prev == nil then
			return nil
		end

		-- check if we have room for more sprites, otherwise shift the existing ones down and add this one to the end
		if #prev.sprites >= prev.max_display_lines and prev.max_display_lines > 0 then
			-- shift the existing sprites down by one (removing the earliest one)
			table.remove(prev.sprites, 1)
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
		table.insert(prev.sprites, sprite)

		return prev
	end
end

return _M