-- Module to parse Sprites sent from phoneside app as TxImageSpriteBlock messages
local _M = {}

-- Parse the image sprite block message raw data. Unpack the header fields.
-- width(Uint16), height(Uint16), sprite_line_height(Uint16), progressive_render(bool as Uint8), updatable(bool as Uint8)
function _M.parse_image_sprite_block(data, prev)
	if string.byte(data, 1) == 0xFF then
		-- new block starting, zero out the old block to get memory back
		if prev ~= nil then
			for k, v in pairs(prev.sprites) do prev.sprites[k] = nil end
			prev = nil
			collectgarbage('collect')
		end

		-- new block
		local image_sprite_block = {}
		image_sprite_block.width = string.byte(data, 2) << 8 | string.byte(data, 3)
		image_sprite_block.height = string.byte(data, 4) << 8 | string.byte(data, 5)
		image_sprite_block.sprite_line_height = string.byte(data, 6) << 8 | string.byte(data, 7)
		image_sprite_block.progressive_render = string.byte(data, 8) == 1
		image_sprite_block.updatable = string.byte(data, 9) == 1
		image_sprite_block.sprites = {}
		-- WARNING: minifier stripped parentheses from the following line and introduced a bug so split division to separate line
		local sprite_height_temp = image_sprite_block.height + image_sprite_block.sprite_line_height - 1
		image_sprite_block.total_sprites = sprite_height_temp // image_sprite_block.sprite_line_height
		image_sprite_block.active_sprites = 0
		image_sprite_block.current_sprite_index = 0
		return image_sprite_block
	-- Otherwise this is a TxSprite, so parse it
	else
		-- no existing ImageSpriteBlock to accumulate into, drop this sprite
		if prev == nil then
			return nil
		end

		-- increment our counters (and index into sprites table)
		prev.current_sprite_index = prev.current_sprite_index + 1
		if prev.current_sprite_index > prev.total_sprites then
			if prev.updatable then
				-- image sprite block is getting updated, return to first sprite
				prev.current_sprite_index = 1
			else
				-- not updatable, drop this sprite
				return prev
			end
		end

		-- we just accumulate up to total_sprites then stop
		if prev.active_sprites < prev.total_sprites then
			prev.active_sprites = prev.active_sprites + 1
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

		-- add this sprite to the current slot
		prev.sprites[prev.current_sprite_index] = sprite

		return prev
	end
end

function _M.set_palette(num_colors, palette_data)
	local colors = {'VOID', 'WHITE', 'GREY', 'RED', 'PINK', 'DARKBROWN','BROWN', 'ORANGE', 'YELLOW', 'DARKGREEN', 'GREEN', 'LIGHTGREEN', 'NIGHTBLUE', 'SEABLUE', 'SKYBLUE', 'CLOUDBLUE'}

	-- we usually wouldn't want to reassign VOID, so the first entry should be black but we won't force it
	for i=1,num_colors do
		local col_offset = (i - 1) * 3

		-- Frame indexes are the color names, Halo indexes are 0-15
		local index
		if frame.HARDWARE_VERSION == 'Frame' then
			index = colors[i]
		else
			index = i - 1
		end

		frame.display.assign_color(index,
			string.byte(palette_data, col_offset + 1),
			string.byte(palette_data, col_offset + 2),
			string.byte(palette_data, col_offset + 3))
	end
end

return _M