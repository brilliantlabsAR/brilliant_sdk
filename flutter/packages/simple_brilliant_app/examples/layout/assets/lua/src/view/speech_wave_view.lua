-- Footer: Speech animation
-- ------------------------
local View = require("view.min")
local SpeechWave = require("speech_wave.min")

local SpeechWaveView = setmetatable({}, {__index = View})
SpeechWaveView.__index = SpeechWaveView
function SpeechWaveView:new(x, y, w, h)
    local obj = View.new(self, x, y, w, h)
    obj.speech_wave = SpeechWave:new(w, h)
    return obj
end

function SpeechWaveView:update(dt)
    if frame.HARDWARE_VERSION ~= 'Frame' then
        self.speech_wave:update(dt) -- TODO no dt handling, just tick
        self:invalidate()
    end
end

function SpeechWaveView:render()
    if frame.HARDWARE_VERSION ~= 'Frame' then
        self:clear()
        self.speech_wave:draw(self.x, self.y)
        self.is_dirty = false
    end
end

return SpeechWaveView