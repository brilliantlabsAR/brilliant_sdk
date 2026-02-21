-- Body: Content area
-- ------------------
local View = require("view")

local BodyView = setmetatable({}, {__index = View})
BodyView.__index = BodyView
function BodyView:render()
    frame.display.text("Hello, Frame!", self.x, self.y)
    frame.display.text("Hello, Frame!", self.x, self.y+20)
    frame.display.text("Hello, Frame!", self.x, self.y+40)
    self.is_dirty = false
end

return BodyView