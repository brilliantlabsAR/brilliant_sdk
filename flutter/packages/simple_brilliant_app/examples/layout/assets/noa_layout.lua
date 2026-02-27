local View = require("view")
local BgView = require("bg_view")
local HeaderView = require("header_view")
local TextView = require("text_view")
local SpeechWaveView = require("speech_wave_view")

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
    obj.body   = TextView:new(35, 66, 256-2*35, 85)
    obj.footer = SpeechWaveView:new(60, 151, 256-2*60, 50)
    
    return obj
end

function NoaLayout:update(dt)
    -- Update children and mark layout dirty if any child becomes dirty
    for _, name in ipairs({"bg", "header", "body", "footer"}) do
        local child = self[name]
        if child and child.update then
            child:update(dt)
            if child.is_dirty then
                self.is_dirty = true
            end
        end
    end
end

function NoaLayout:render()
    if not self.is_dirty then return end

    -- 1. Redraw everything in order
    for _, name in ipairs({"bg", "header", "body", "footer"}) do
        local child = self[name]
        if child and child.is_dirty then
            child:clear()
            child:render()
            child.is_dirty = false
        end
    end

    -- 2. Clean the NoaLayout dirty flag
    self.is_dirty = false
end

return NoaLayout
