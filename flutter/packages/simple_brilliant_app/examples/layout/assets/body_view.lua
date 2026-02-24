-- Body: Content area
-- ------------------
local View = require("view")

local BodyView = setmetatable({}, {__index = View})
BodyView.__index = BodyView
function BodyView:render()
    if self.lines then
        for i, spr in ipairs(self.lines) do
            local y_offset = self.y + (i-1) * self.line_height
            -- center the text sprites horizontally within the body view
            local x_offset = self.x + (self.w - spr.width) // 2
            frame.display.bitmap(x_offset, y_offset, spr.width, 2^spr.bpp, 0, spr.pixel_data)
        end
    end
    self.is_dirty = false
end

function BodyView:set_lines(lines, line_height)
    self.lines = lines
    self.line_height = line_height
    self:invalidate()
end

function BodyView:clear_lines()
    for k in pairs(self.lines) do self.lines[k] = nil end
    self.lines = nil
    self:invalidate()
end

return BodyView