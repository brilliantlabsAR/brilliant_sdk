-- Header: Notification area
-- -------------------------
local View = require("view")

local HeaderView = setmetatable({}, {__index = View})
HeaderView.__index = HeaderView
function HeaderView:set_recording(is_recording)
    self.is_recording = is_recording
    self:invalidate()
end
function HeaderView:render()
    local col = 0x000000
    if self.is_recording then
        col = 0xF00000
    end

    frame.display.circle(self.x+8, self.y+10, 8, col, true)
    self.is_dirty = false
end

return HeaderView