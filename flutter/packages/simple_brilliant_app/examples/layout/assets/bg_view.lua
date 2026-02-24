-- Background view (battery indicator plus circle)
-- -----------------------------------------------
local View = require("view")

local BgView = setmetatable({}, {__index = View})
BgView.__index = BgView
function BgView:render()
    -- blue background
    frame.display.clear(0x4444FF)
    -- black circle
    frame.display.circle(127, 127, 120, 0x000000, true)
    self.is_dirty = false
end

return BgView