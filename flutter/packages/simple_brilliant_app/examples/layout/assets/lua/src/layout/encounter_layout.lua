-- encounter_layout.lua
local BaseLayout = require("base_layout.min")
local HeaderView = require("header_view.min")
local TextView = require("text_view.min")
local ImageView = require("image_view.min") 

local EncounterLayout = setmetatable({}, {__index = BaseLayout})
EncounterLayout.__index = EncounterLayout

function EncounterLayout:new()
    local obj = BaseLayout:new(0, 0, 256, 256)
    obj.type = "EncounterLayout"
    
    -- Add children in the order they should be updated/rendered
    obj:add_child("header", HeaderView:new(120, 30, 256-2*120, 20))
    obj:add_child("body", TextView:new(55, 50, 146, 60))
    obj:add_child("image", ImageView:new(64, 110, 128, 128))
    
    return obj
end

return EncounterLayout