-- encounter_layout.lua
local BaseLayout = require("base_layout")
local BgView = require("bg_view")
local HeaderView = require("header_view")
local TextView = require("text_view")
local ImageView = require("image_view") 

local EncounterLayout = setmetatable({}, {__index = BaseLayout})
EncounterLayout.__index = EncounterLayout

function EncounterLayout:new()
    local obj = BaseLayout.new(self, 0, 0, 256, 256)
    
    -- Add children in the order they should be updated/rendered
    obj:add_child("bg", BgView:new(0, 0, 256, 256))
    obj:add_child("header", HeaderView:new(120, 30, 256-2*120, 20))
    obj:add_child("body", TextView:new(35, 66, 186, 85))
    obj:add_child("footer", ImageView:new(64, 127, 128, 128))
    
    return obj
end

return EncounterLayout