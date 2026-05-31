-- Module to parse text strings sent from phoneside app as TxPlainText messages
local _M = {}

local colors = {'VOID', 'WHITE', 'GREY', 'RED', 'PINK', 'DARKBROWN','BROWN', 'ORANGE', 'YELLOW', 'DARKGREEN', 'GREEN', 'LIGHTGREEN', 'NIGHTBLUE', 'SEABLUE', 'SKYBLUE', 'CLOUDBLUE'}

-- Parse the TxPlainText message raw data, which is a string
function _M.parse_plain_text(data)
	local plain_text = {}

	plain_text.x = string.byte(data, 1) << 8 | string.byte(data, 2)
	plain_text.y = string.byte(data, 3) << 8 | string.byte(data, 4)
	plain_text.palette_offset = string.byte(data, 5)
	plain_text.color = colors[plain_text.palette_offset % 16 + 1]
	plain_text.spacing = string.byte(data, 6)
	plain_text.string = string.sub(data, 7)

	return plain_text
end

return _M