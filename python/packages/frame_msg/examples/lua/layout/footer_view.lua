-- Footer: Speech animation
-- ------------------------
local View = require("view")

local FooterView = setmetatable({}, {__index = View})
FooterView.__index = FooterView
function FooterView:new(x, y, w, h)
    local obj = View.new(self, x, y, w, h)
    obj.anim_time = 0
    return obj
end

function FooterView:update(dt)
    self.anim_time = self.anim_time + dt
    --self:invalidate() 
end

function FooterView:render()
    frame.display.text("Speaking...", self.x+5, self.y+15)
    self.is_dirty = false
end

return FooterView