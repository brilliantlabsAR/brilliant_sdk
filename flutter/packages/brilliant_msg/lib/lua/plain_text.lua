-- Module to parse text strings sent from phoneside app as TxPlainText messages
local _M = {}

local colors = {'VOID', 'WHITE', 'GREY', 'RED', 'PINK', 'DARKBROWN','BROWN', 'ORANGE', 'YELLOW', 'DARKGREEN', 'GREEN', 'LIGHTGREEN', 'NIGHTBLUE', 'SEABLUE', 'SKYBLUE', 'CLOUDBLUE'}
local colors_hex = {
	0x000000, -- VOID
	0xFFFFFF, -- WHITE
	0x808080, -- GREY
	0xFF0000, -- RED
	0xFFC0CB, -- PINK
	0x654321, -- DARKBROWN
	0x964B00, -- BROWN
	0xFFA500, -- ORANGE
	0xFFFF00, -- YELLOW
	0x006400, -- DARKGREEN
	0x00FF00, -- GREEN
	0x90EE90, -- LIGHTGREEN
	0x191970, -- NIGHTBLUE
	0x0000CD, -- SEABLUE
	0x87CEEB, -- SKYBLUE
	0xF0F8FF, -- CLOUDBLUE
}

-- Parse the TxPlainText message raw data, which is a string
function _M.parse_plain_text(data)
	local plain_text = {}

	plain_text.x = string.byte(data, 1) << 8 | string.byte(data, 2)
	plain_text.y = string.byte(data, 3) << 8 | string.byte(data, 4)
	plain_text.palette_offset = string.byte(data, 5)
	if frame.HARDWARE_VERSION ~= 'Frame' then
		plain_text.color = colors_hex[plain_text.palette_offset % 16 + 1]
	else
		plain_text.color = colors[plain_text.palette_offset % 16 + 1]
	end
	plain_text.spacing = string.byte(data, 6)
	plain_text.string = string.sub(data, 7)

	return plain_text
end

return _M