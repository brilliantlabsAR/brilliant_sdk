local View = require("view")
local BgView = require("bg_view")
local HeaderView = require("header_view")
local BodyView = require("body_view")
local FooterView = require("footer_view")

-- NoaLayout: Combines all views and manages updates/renders
-- Noa-specific layout with header, body, footer, and background views
-- ---------------------------------------------------------
local NoaLayout = setmetatable({}, {__index = View})
NoaLayout.__index = NoaLayout

function NoaLayout:new()
    local obj = View.new(self, 0, 0, 256, 256)
    
    -- Set proportions on instantiation
    obj.bg     = BgView:new(0, 0, 256, 256)
    obj.header = HeaderView:new(120, 30, 256-2*120, 20)
    obj.body   = BodyView:new(20, 76, 256-2*20, 100)
    obj.footer = FooterView:new(60, 176, 256-2*60, 50)
    
    return obj
end

function NoaLayout:update(dt)
    -- Update all children
    self.bg:update(dt)
    self.header:update(dt)
    self.body:update(dt)
    self.footer:update(dt)

    -- Check if we need to redraw the whole screen
    -- If any child is dirty, the whole layout is considered dirty
    if self.bg.is_dirty or self.header.is_dirty or self.body.is_dirty or self.footer.is_dirty then
        self.is_dirty = true
    end
end

function NoaLayout:render()
    if not self.is_dirty then return end

    -- 1. Redraw everything in order
    if self.bg.is_dirty then
        self.bg:clear()
        self.bg:render()
        self.bg.is_dirty = false
    end
    if self.header.is_dirty then
        self.header:clear()
        self.header:render()
        self.header.is_dirty = false
    end
    if self.body.is_dirty then
        self.body:clear()
        self.body:render()
        self.body.is_dirty = false
    end
    if self.footer.is_dirty then
        self.footer:clear()
        self.footer:render()
        self.footer.is_dirty = false
    end

    -- 2. Clean the NoaLayout dirty flag
    self.is_dirty = false
end

return NoaLayout
