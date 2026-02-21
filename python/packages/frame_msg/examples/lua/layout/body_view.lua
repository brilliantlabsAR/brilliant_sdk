-- Body: Content area
-- ------------------
local View = require("view")

local BodyView = setmetatable({}, {__index = View})
BodyView.__index = BodyView
function BodyView:render()
    if self.lines then
        for i, line in ipairs(self.lines) do
            frame.display.text(line, self.x, self.y + 20 * (i-1))
        end
    end
    self.is_dirty = false
end

function BodyView:push_line(line)
    if not self.lines then self.lines = {} end
    table.insert(self.lines, line)
    if #self.lines > 3 then
        table.remove(self.lines, 1) -- keep only last 3 lines
    end
    self:invalidate()
end

return BodyView