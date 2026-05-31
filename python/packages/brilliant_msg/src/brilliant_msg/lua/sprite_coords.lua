-- Module to parse sprite coordinates sent from phoneside app as TxSpriteCoords messages
local _M = {}

-- Parse the TxSpriteCoords message raw data
function _M.parse_sprite_coords(data)
    local sprite_coords = {}

    sprite_coords.code = string.byte(data, 1)
    sprite_coords.x = string.byte(data, 2) << 8 | string.byte(data, 3)
    sprite_coords.y = string.byte(data, 4) << 8 | string.byte(data, 5)
    sprite_coords.offset = string.byte(data, 6)

    return sprite_coords
end

return _M