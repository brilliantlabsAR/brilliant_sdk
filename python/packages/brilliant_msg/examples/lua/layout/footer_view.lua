-- Footer: Speech animation
-- ------------------------
local View = require("view")
local SpeechWave = require("speech_wave")

local FooterView = setmetatable({}, {__index = View})
FooterView.__index = FooterView
function FooterView:new(x, y, w, h)
    local obj = View.new(self, x, y, w, h)
    obj.speech_wave = SpeechWave:new(w, h)
    return obj
end

function FooterView:update(dt)
    self.speech_wave:update(dt) -- TODO no dt handling, just tick
    self:invalidate() 
end

function FooterView:render()
    self.speech_wave:draw(self.x, self.y)
    self.is_dirty = false
end

return FooterView