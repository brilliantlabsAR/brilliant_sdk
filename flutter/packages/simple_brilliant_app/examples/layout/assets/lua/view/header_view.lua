-- Header: Notification area
-- -------------------------
local View = require("view.min")

local HeaderView = setmetatable({}, {__index = View})
HeaderView.__index = HeaderView
function HeaderView:set_recording(is_recording)
    self.is_recording = is_recording
    self:invalidate()
end
function HeaderView:render()
    if frame.HARDWARE_VERSION ~= 'Frame' then
        -- draw a red circle in the top-left corner if recording, black otherwise
        local col = self.is_recording and 0xF00000 or 0x000000
        frame.display.circle(self.x+8, self.y+10, 8, col, true)
    else
        -- on Frame, draw a small red rectangle in the top bar if recording, otherwise nothing
        if self.is_recording then
            frame.display.assign_color('RED', 255, 0, 0)
            -- 16x16 square, 2-colour bitmap, red is offset 3
            frame.display.bitmap(self.x+8, self.y+10, 16, 2, 3, string.rep("\xFF", 32))
        end
    end

    self.is_dirty = false
end

return HeaderView