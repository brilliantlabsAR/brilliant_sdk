-- Module to parse Sprites sent from phoneside app as TxSprite messages
local _M = {}

-- Parse the sprite message raw data. Unpack the header fields.
-- width(Uint16), height(Uint16), bpp(Uint8), numColors(Uint8), palette (Uint8 r, Uint8 g, Uint8 b)*numColors, data (length width x height x bpp/8)
function _M.parse_sprite(data)
	local sprite = {}
	sprite.width = string.byte(data, 1) << 8 | string.byte(data, 2)
	sprite.height = string.byte(data, 3) << 8 | string.byte(data, 4)
	sprite.compressed = string.byte(data, 5) > 0
	sprite.bpp = string.byte(data, 6)
	sprite.num_colors = string.byte(data, 7)
	sprite.palette_data = string.sub(data, 8, 8 + sprite.num_colors * 3 - 1)
	sprite.pixel_data = string.sub(data, 8 + sprite.num_colors * 3)
	return sprite
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