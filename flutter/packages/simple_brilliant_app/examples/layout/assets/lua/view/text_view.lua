-- Body: Content area
-- ------------------
local View = require("view")

local TextView = setmetatable({}, {__index = View})
TextView.__index = TextView
function TextView:render()
    if self.lines then
        for i, spr in ipairs(self.lines) do
            local y_offset = self.y + (i-1) * self.line_height
            -- center the text sprites horizontally within the body view
            local x_offset = self.x + (self.w - spr.width) // 2
            local col = frame.HARDWARE_VERSION ~= 'Frame' and 1 or 'WHITE'
            frame.display.assign_color(col, 255, 255, 255) -- TODO ideally the text sprites would come with their own palette data so we don't have to hardcode this
            frame.display.bitmap(x_offset, y_offset, spr.width, 2^spr.bpp, 0, spr.pixel_data)
        end
    end
    self.is_dirty = false
end

function TextView:set_lines(lines, line_height)
    self.lines = lines
    self.line_height = line_height
    self:invalidate()
end

function TextView:clear_lines()
    if self.lines then
        for k in pairs(self.lines) do self.lines[k] = nil end
        self.lines = nil
    end
    self:invalidate()
end

return TextView