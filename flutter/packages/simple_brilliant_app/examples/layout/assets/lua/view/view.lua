-- Base View class
-- --------------------------------------------
local View = {}
View.__index = View

function View:new(x, y, w, h)
    local instance = {
        x = x, y = y, w = w, h = h,
        is_dirty = true
    }
    return setmetatable(instance, self)
end

function View:invalidate()
    self.is_dirty = true
end

function View:update(dt) 
    -- Base view does nothing, subclasses override this
end

function View:clear()
    -- Frame clears on every redraw, no need (and doesn't support rect)
    if frame.HARDWARE_VERSION ~= 'Frame' then
        -- Base view draw logic (e.g., just a black rectangle)
        frame.display.rect(self.x, self.y, self.w, self.h, 0x000000, true)
        -- debug red border to visualize view boundaries
        -- frame.display.rect(self.x, self.y, self.w, self.h, 0xA00000, false)
    end
end

function View:render()
    -- Base view draw logic (e.g., just a background clear)
end

return View