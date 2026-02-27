-- speech_layout.lua
local BaseLayout = require("base_layout")
local BgView = require("bg_view")
local HeaderView = require("header_view")
local SpeechWaveView = require("speech_wave_view") 

local SpeechLayout = setmetatable({}, {__index = BaseLayout})
SpeechLayout.__index = SpeechLayout

function SpeechLayout:new()
    local obj = BaseLayout.new(self, 0, 0, 256, 256)
    
    obj:add_child("bg", BgView:new(0, 0, 256, 256))
    obj:add_child("header", HeaderView:new(120, 30, 256-2*120, 20))
    obj:add_child("body", SpeechWaveView:new(60, 102, 136, 50))
    
    return obj
end

return SpeechLayout