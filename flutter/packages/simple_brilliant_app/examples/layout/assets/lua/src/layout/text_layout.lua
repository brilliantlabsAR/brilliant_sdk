-- text_layout.lua
local BaseLayout = require("base_layout.min")
local BgView = require("bg_view.min")
local HeaderView = require("header_view.min")
local TextView = require("text_view.min")

local TextLayout = setmetatable({}, {__index = BaseLayout})
TextLayout.__index = TextLayout

function TextLayout:new()
    local obj = BaseLayout.new(self, 0, 0, 256, 256)
    
    obj:add_child("bg", BgView:new(0, 0, 256, 256))
    obj:add_child("header", HeaderView:new(120, 30, 256-2*120, 20))
    obj:add_child("body", TextView:new(35, 67, 185, 120))
    
    return obj
end

return TextLayout