-- layout.lua
-- Base View class and NoaLayout implementation

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
    -- Base view draw logic (e.g., just a black rectangle)
    frame.display.rect(self.x, self.y, self.w, self.h, 0x000000, true)
    frame.display.rect(self.x, self.y, self.w, self.h, 0xA00000, false)
end

function View:render()
    -- Base view draw logic (e.g., just a background clear)
end

-- Noa-specific layout with header, body, footer, and background views
-- Background view (battery indicator plus circle)
local BgView = setmetatable({}, {__index = View})
BgView.__index = BgView
function BgView:render()
    -- blue background
    frame.display.clear(0x4444FF)
    -- black circle
    frame.display.circle(127, 127, 120, 0x000000, true)
end

-- Header: Notification area
local HeaderView = setmetatable({}, {__index = View})
HeaderView.__index = HeaderView
function HeaderView:set_recording(is_recording)
    print("HeaderView: set_recording called with: " .. tostring(is_recording))
    self.is_recording = is_recording
    self:invalidate()
end
function HeaderView:render()
    print("Rendering header, recording state:" .. tostring(self.is_recording or false))
    local col = 0x000000
    if self.is_recording then
        print("Header is in recording state, using red color")
        col = 0xF00000
    end

    frame.display.circle(self.x+8, self.y+10, 8, col, true)
end

-- Body: Content area
local BodyView = setmetatable({}, {__index = View})
BodyView.__index = BodyView
function BodyView:render()
    frame.display.text("Hello, Frame!", self.x, self.y)
    frame.display.text("Hello, Frame!", self.x, self.y+20)
    frame.display.text("Hello, Frame!", self.x, self.y+40)
end

-- Footer: Speech animation
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
end

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
        print("NoaLayout marked dirty due to child view")
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

    -- 2. Clean the flags
    self.is_dirty = false
end

return {
    NoaLayout = NoaLayout
}
